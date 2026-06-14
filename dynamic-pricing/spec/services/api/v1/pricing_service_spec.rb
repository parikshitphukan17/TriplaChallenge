require "rails_helper"

RSpec.describe Api::V1::PricingService, type: :service do
  ['rails_cache', 'redis'].each do |provider_type|
    context "with #{provider_type} cache provider" do
      before do
        @old_cache_provider_type = ENV['CACHE_PROVIDER_TYPE']
        ENV['CACHE_PROVIDER_TYPE'] = provider_type
        Api::V1::PricingService.reset_cache_provider!

        if provider_type == 'rails_cache'
          @old_cache = Rails.cache
          Rails.cache = ActiveSupport::Cache::MemoryStore.new
        end
        Api::V1::PricingService.cache_provider.clear_cache
      end

      after do
        Api::V1::PricingService.cache_provider.clear_cache
        if provider_type == 'rails_cache'
          Rails.cache = @old_cache
        end
        ENV['CACHE_PROVIDER_TYPE'] = @old_cache_provider_type
        Api::V1::PricingService.reset_cache_provider!
      end

      it "returns rate from cache on valid hit" do
        rates_data = {
          "Summer:FloatingPointResort:SingletonRoom" => "12345"
        }
        Api::V1::PricingService.cache_provider.write_rates(rates_data)

        service = Api::V1::PricingService.new(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        service.run

        expect(service.valid?).to be true
        expect(service.result).to eq("12345")
        expect(service.disclaimer).to be_nil
      end

      it "serves stale rates with disclaimer and triggers async refresh when sync refresh fails" do
        rates_data = {
          "Summer:FloatingPointResort:SingletonRoom" => "12345"
        }
        # Cache rates fetched 10 minutes ago
        Api::V1::PricingService.cache_provider.write_rates(rates_data, fetched_at: 10.minutes.ago)

        expect(RefreshRatesJob).to receive(:perform_later)

        # Stub the synchronous perform call to fail
        allow_any_instance_of(RefreshRatesJob).to receive(:perform).and_return(false)

        service = Api::V1::PricingService.new(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        service.run

        expect(service.valid?).to be true
        expect(service.result).to eq("12345")
        expect(service.disclaimer).to match(/expired/)
      end

      it "returns latest rates without disclaimer when sync refresh succeeds on expired cache" do
        rates_data = {
          "Summer:FloatingPointResort:SingletonRoom" => "12345"
        }
        Api::V1::PricingService.cache_provider.write_rates(rates_data, fetched_at: 10.minutes.ago)

        # Stub the update behavior of the job
        allow_any_instance_of(RefreshRatesJob).to receive(:perform).and_wrap_original do |m, *args|
          Api::V1::PricingService.cache_provider.write_rates({ "Summer:FloatingPointResort:SingletonRoom" => "99999" })
          true
        end

        service = Api::V1::PricingService.new(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        service.run

        expect(service.valid?).to be true
        expect(service.result).to eq("99999")
        expect(service.disclaimer).to be_nil
      end

      it "serves stale rates immediately when lock is held on expired cache" do
        rates_data = {
          "Summer:FloatingPointResort:SingletonRoom" => "12345"
        }
        Api::V1::PricingService.cache_provider.write_rates(rates_data, fetched_at: 10.minutes.ago)

        # Set the lock key to simulate another process holding the lock
        lock_key = "dynamic_pricing:refresh_lock"
        Api::V1::PricingService.cache_provider.acquire_lock(lock_key, 2.minutes)

        service = Api::V1::PricingService.new(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        # Confirm it does not block/sleep
        expect(service).not_to receive(:sleep)

        service.run

        expect(service.valid?).to be true
        expect(service.result).to eq("12345")
        expect(service.disclaimer).to match(/expired/)

        Api::V1::PricingService.cache_provider.release_lock(lock_key)
      end

      it "returns error on cold start if API is down" do
        # Ensure cache is empty
        Api::V1::PricingService.cache_provider.clear_cache

        # Stub the refresh job to fail
        allow_any_instance_of(RefreshRatesJob).to receive(:perform).and_return(false)

        service = Api::V1::PricingService.new(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        service.run

        expect(service.valid?).to be false
        expect(service.errors).to include("Rates are unavailable and cache is empty. Please retry in 5 minutes.")
      end

      it "supports caching and locking in provider" do
        lock_key = "test_concurrency_lock"

        # Acquire lock
        expect(Api::V1::PricingService.cache_provider.acquire_lock(lock_key, 5.seconds)).to be true

        # Acquire lock again (should fail)
        expect(Api::V1::PricingService.cache_provider.acquire_lock(lock_key, 5.seconds)).to be false

        # Release lock
        Api::V1::PricingService.cache_provider.release_lock(lock_key)

        # Acquire lock again (should succeed now)
        expect(Api::V1::PricingService.cache_provider.acquire_lock(lock_key, 5.seconds)).to be true
        Api::V1::PricingService.cache_provider.release_lock(lock_key)
      end

      it "retries on API failure and eventually succeeds" do
        call_count = 0
        mock_get_rates = lambda do |*args|
          call_count += 1
          if call_count < 3
            OpenStruct.new(success?: false, code: 500, body: "Server Error")
          else
            mock_body = {
              'rates' => [
                { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '22222' }
              ]
            }.to_json
            OpenStruct.new(success?: true, body: mock_body)
          end
        end

        allow(RateApiClient).to receive(:get_rates).and_wrap_original do |m, *args|
          mock_get_rates.call(*args)
        end

        job = RefreshRatesJob.new
        allow(job).to receive(:sleep)

        expect(job.perform).to be true
        expect(call_count).to eq(3)

        # Cache should be populated now
        rates_payload = Api::V1::PricingService.cache_provider.read_rates
        expect(rates_payload[:rates]["Summer:FloatingPointResort:SingletonRoom"]).to eq("22222")
      end

      it "successfully reads and writes all 36 valid pricing key combinations" do
        rates_hash = {}
        combinations = []

        Api::V1::PricingController::VALID_PERIODS.each do |period|
          Api::V1::PricingController::VALID_HOTELS.each do |hotel|
            Api::V1::PricingController::VALID_ROOMS.each do |room|
              key = Api::V1::PricingService.cache_key(period: period, hotel: hotel, room: room)
              rates_hash[key] = "price_#{period}_#{hotel}_#{room}"
              combinations << { period: period, hotel: hotel, room: room }
            end
          end
        end

        # Write to cache
        Api::V1::PricingService.cache_provider.write_rates(rates_hash)

        # Assert that all 36 combinations resolve correctly
        combinations.each do |combo|
          service = Api::V1::PricingService.new(
            period: combo[:period],
            hotel: combo[:hotel],
            room: combo[:room]
          )
          service.run

          expect(service.valid?).to be(true), "Failed for combo: #{combo}"
          expected_price = "price_#{combo[:period]}_#{combo[:hotel]}_#{combo[:room]}"
          expect(service.result).to eq(expected_price)
          expect(service.disclaimer).to be_nil
        end
      end

      it "generates correct cache key format" do
        key = Api::V1::PricingService.cache_key(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        expect(key).to eq("Summer:FloatingPointResort:SingletonRoom")
      end

      it "skips sync refresh and returns stale rates immediately if cool-down is active" do
        rates_data = {
          "Summer:FloatingPointResort:SingletonRoom" => "12345"
        }
        Api::V1::PricingService.cache_provider.write_rates(rates_data, fetched_at: 10.minutes.ago)

        # Set cool-down key in cache
        Api::V1::PricingService.cache_provider.activate_cool_down(
          RefreshRatesJob::COOL_DOWN_KEY,
          RefreshRatesJob::COOL_DOWN_DURATION
        )

        # If the system tries to perform, we expect it should NOT happen
        expect(RefreshRatesJob).not_to receive(:new)

        service = Api::V1::PricingService.new(
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        )
        service.run

        expect(service.valid?).to be true
        expect(service.result).to eq("12345")
        expect(service.disclaimer).to match(/expired/)
      end

      it "writes cool-down key to cache when job fails and all retries are exhausted" do
        mock_get_rates = lambda do |*args|
          OpenStruct.new(success?: false, code: 500, body: "Fatal Outage")
        end

        allow(RateApiClient).to receive(:get_rates).and_wrap_original do |m, *args|
          mock_get_rates.call(*args)
        end

        job = RefreshRatesJob.new
        allow(job).to receive(:sleep)

        expect(job.perform).to be false
        expect(Api::V1::PricingService.cache_provider.cool_down_active?(RefreshRatesJob::COOL_DOWN_KEY)).to be true
      end

      it "skips job perform immediately if cool-down is active" do
        # Activate cool-down key
        Api::V1::PricingService.cache_provider.activate_cool_down(
          RefreshRatesJob::COOL_DOWN_KEY,
          RefreshRatesJob::COOL_DOWN_DURATION
        )

        expect(RateApiClient).not_to receive(:get_rates)

        job = RefreshRatesJob.new
        expect(job.perform).to be false
      end
    end
  end
end
