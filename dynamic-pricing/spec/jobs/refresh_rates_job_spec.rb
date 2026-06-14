require 'rails_helper'

RSpec.describe RefreshRatesJob, type: :job do
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

      describe '#perform' do
        let(:job) { RefreshRatesJob.new }
        let(:lock_key) { "dynamic_pricing:refresh_lock" }

        context 'when execution is successful' do
          let(:mock_rates_response) do
            {
              rates: [
                { period: "Summer", hotel: "FloatingPointResort", room: "SingletonRoom", rate: 12500 }
              ]
            }.to_json
          end

          before do
            allow(RateApiClient).to receive(:get_rates).and_return(
              OpenStruct.new(success?: true, code: 200, body: mock_rates_response)
            )
            allow(Observability::Metrics).to receive(:observe_job_duration)
            allow(Observability::Metrics).to receive(:set_circuit_breaker)
          end

          it 'acquires lock, retrieves rates, populates the cache, releases the lock, and records metrics' do
            expect(Api::V1::PricingService.cache_provider).to receive(:acquire_lock).with(lock_key, 2.minutes).and_call_original
            expect(Api::V1::PricingService.cache_provider).to receive(:release_lock).with(lock_key).and_call_original

            expect(job.perform).to be true

            # Verify cache is populated
            rates_payload = Api::V1::PricingService.cache_provider.read_rates
            expect(rates_payload).not_to be_nil
            expect(rates_payload[:rates]["Summer:FloatingPointResort:SingletonRoom"]).to eq(12500)

            # Verify metrics recorded
            expect(Observability::Metrics).to have_received(:set_circuit_breaker).with(false).at_least(:once)
            expect(Observability::Metrics).to have_received(:observe_job_duration).with(kind_of(Numeric))
          end
        end

        context 'when another job is already running (lock is held)' do
          before do
            # Acquire lock to simulate concurrent worker
            Api::V1::PricingService.cache_provider.acquire_lock(lock_key, 2.minutes)
            allow(RateApiClient).to receive(:get_rates)
          end

          after do
            Api::V1::PricingService.cache_provider.release_lock(lock_key)
          end

          it 'skips execution and returns false' do
            expect(job.perform).to be false
            expect(RateApiClient).not_to have_received(:get_rates)
          end
        end

        context 'when cool-down is active' do
          before do
            Api::V1::PricingService.cache_provider.activate_cool_down(
              RefreshRatesJob::COOL_DOWN_KEY,
              RefreshRatesJob::COOL_DOWN_DURATION
            )
            allow(RateApiClient).to receive(:get_rates)
            allow(Observability::Metrics).to receive(:set_circuit_breaker)
          end

          it 'skips execution, sets circuit breaker, and returns false' do
            expect(job.perform).to be false
            expect(RateApiClient).not_to have_received(:get_rates)
            expect(Observability::Metrics).to have_received(:set_circuit_breaker).with(true)
          end
        end

        context 'when the upstream API fails' do
          before do
            allow(RateApiClient).to receive(:get_rates).and_return(
              OpenStruct.new(success?: false, code: 500, body: 'Upstream Failure')
            )
            allow(Observability::Metrics).to receive(:observe_upstream_failure)
            allow(Observability::Metrics).to receive(:observe_upstream_retry)
            allow(Observability::Metrics).to receive(:observe_job_failure)
            allow(Observability::Metrics).to receive(:set_circuit_breaker)
          end

          it 'retries 3 times with exponential backoff and random jitter, then triggers cool-down' do
            sleep_times = []
            allow(job).to receive(:sleep) do |time|
              sleep_times << time
            end

            expect(job.perform).to be false

            expect(sleep_times.size).to eq(2)
            # Attempt 1 failed: backoff_base = 2, range should be 0.0..2.0
            expect(sleep_times[0]).to be_between(0.0, 2.0)
            # Attempt 2 failed: backoff_base = 4, range should be 0.0..4.0
            expect(sleep_times[1]).to be_between(0.0, 4.0)

            # Verify cool-down is activated
            expect(Api::V1::PricingService.cache_provider.cool_down_active?(RefreshRatesJob::COOL_DOWN_KEY)).to be true

            # Verify metrics
            expect(Observability::Metrics).to have_received(:observe_upstream_failure).with("http_500").exactly(3).times
            expect(Observability::Metrics).to have_received(:observe_upstream_retry).exactly(2).times
            expect(Observability::Metrics).to have_received(:observe_job_failure).once
            expect(Observability::Metrics).to have_received(:set_circuit_breaker).with(true).once
          end
        end

        context 'when upstream API times out' do
          before do
            allow(RateApiClient).to receive(:get_rates).and_raise(Timeout::Error.new("Request timed out"))
            allow(Observability::Metrics).to receive(:observe_upstream_failure)
            allow(job).to receive(:sleep)
          end

          it 'correctly classifies as a timeout error and retries' do
            expect(job.perform).to be false
            expect(Observability::Metrics).to have_received(:observe_upstream_failure).with("timeout").exactly(3).times
          end
        end
      end
    end
  end
end
