module Api::V1
  class PricingService < BaseService
    attr_reader :disclaimer

    def self.cache_provider
      @cache_provider ||= begin
        provider_type = ENV.fetch('CACHE_PROVIDER_TYPE', 'rails_cache')
        case provider_type.to_s.downcase
        when 'redis'
          Api::V1::CacheProviders::RedisProvider.new
        else
          Api::V1::CacheProviders::RailsCacheProvider.new
        end
      end
    end

    def self.cache_key(period:, hotel:, room:)
      "#{period}:#{hotel}:#{room}"
    end

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
      @disclaimer = nil
    end

    def run
      if caching_disabled?
        run_direct_fetch
        return
      end

      payload = PricingService.cache_provider.read_rates

      if payload.nil?
        payload = handle_cold_start
      elsif cache_expired?(payload)
        payload = refresh_expired_cache(payload)
      end

      process_payload(payload)
    end

    private

    def caching_disabled?
      Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    end

    def run_direct_fetch
      rate = RateApiClient.get_rate(period: @period, hotel: @hotel, room: @room)
      if rate.success?
        parsed_rate = rate.body.is_a?(Hash) ? rate.body : JSON.parse(rate.body)
        @result = parsed_rate['rates'].detect { |r| r['period'] == @period && r['hotel'] == @hotel && r['room'] == @room }&.dig('rate')
      else
        errors << extract_error_message(rate)
      end
    end

    def extract_error_message(rate)
      if rate.body.is_a?(Hash)
        rate.body['error']
      else
        JSON.parse(rate.body)['error'] rescue rate.body
      end
    end

    def cache_expired?(payload)
      Time.current - payload[:fetched_at] > 5.minutes
    end

    def handle_cold_start
      # Cold Start: Cache is empty. We must block and fetch synchronously.
      success = RefreshRatesJob.new.perform

      if success
        PricingService.cache_provider.read_rates
      else
        wait_for_other_worker_warmup
      end
    end

    def wait_for_other_worker_warmup
      # Spin-lock: wait up to 1 second for the other process to finish and update cache
      payload = nil
      10.times do
        sleep 0.1
        payload = PricingService.cache_provider.read_rates
        break if payload
      end
      payload
    end

    def refresh_expired_cache(payload)
      cool_down_key = "dynamic_pricing:api_cool_down"
      return payload if PricingService.cache_provider.cool_down_active?(cool_down_key)

      lock_key = "dynamic_pricing:refresh_lock"
      return payload if PricingService.cache_provider.lock_held?(lock_key)

      # Lock is free. Try fetching synchronously.
      success = RefreshRatesJob.new.perform
      if success
        PricingService.cache_provider.read_rates
      else
        # Sync fetch failed (API down). Fallback to stale and enqueue async retry.
        RefreshRatesJob.perform_later
        payload
      end
    end

    def process_payload(payload)
      if payload
        rate_key = self.class.cache_key(period: @period, hotel: @hotel, room: @room)
        rate_value = payload[:rates][rate_key]

        if rate_value
          @result = rate_value
          set_stale_disclaimer_if_needed(payload, rate_key)
        else
          errors << "Rate not found for the requested parameters."
        end
      else
        errors << "Rates are unavailable and cache is empty. Please retry in 5 minutes."
        Rails.logger.error("Failed to retrieve rates: Cache is empty and upstream API is offline.")
      end
    end

    def set_stale_disclaimer_if_needed(payload, rate_key)
      if cache_expired?(payload)
        @disclaimer = "Rates are expired, please retry again in at least 5 minutes to get latest rate"
        Rails.logger.warn("Serving stale rate for #{rate_key} (fetched_at: #{payload[:fetched_at]})")
      end
    end
  end
end
