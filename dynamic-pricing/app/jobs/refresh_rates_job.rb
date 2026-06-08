class RefreshRatesJob < ApplicationJob
  queue_as :default

  COOL_DOWN_KEY = "dynamic_pricing:api_cool_down".freeze
  COOL_DOWN_DURATION = 10.minutes

  def perform(*args)
    if Api::V1::PricingService.cache_provider.cool_down_active?(COOL_DOWN_KEY)
      Rails.logger.info("RefreshRatesJob skipped: API cool-down is active.")
      return false
    end

    lock_key = "dynamic_pricing:refresh_lock"
    # Acquire lock for 2 minutes to prevent concurrent fetches
    unless Api::V1::PricingService.cache_provider.acquire_lock(lock_key, 2.minutes)
      Rails.logger.info("RefreshRatesJob skipped: lock '#{lock_key}' is already held.")
      return false
    end

    max_attempts = 3
    attempt = 0
    backoff_base = 2.seconds

    begin
      attempt += 1
      Rails.logger.info("RefreshRatesJob started (attempt #{attempt}/#{max_attempts}): fetching fresh rates from upstream API...")

      combinations = []
      Api::V1::PricingController::VALID_PERIODS.each do |period|
        Api::V1::PricingController::VALID_HOTELS.each do |hotel|
          Api::V1::PricingController::VALID_ROOMS.each do |room|
            combinations << { period: period, hotel: hotel, room: room }
          end
        end
      end

      response = RateApiClient.get_rates(combinations)
      if response.success?
        parsed = JSON.parse(response.body)
        rates_hash = {}
        parsed['rates'].each do |r|
          key = Api::V1::PricingService.cache_key(period: r['period'], hotel: r['hotel'], room: r['room'])
          rates_hash[key] = r['rate']
        end

        Api::V1::PricingService.cache_provider.write_rates(rates_hash)
        Rails.logger.info("RefreshRatesJob completed successfully. Cached #{rates_hash.size} rates.")
        true
      else
        raise "Upstream API error (HTTP #{response.code}): #{response.body}"
      end
    rescue => e
      Rails.logger.warn("RefreshRatesJob failed on attempt #{attempt}/#{max_attempts}: #{e.message}")
      if attempt < max_attempts
        sleep_time = backoff_base * (2**(attempt - 1))
        Rails.logger.info("Retrying in #{sleep_time} seconds...")
        sleep(sleep_time)
        retry
      else
        Rails.logger.error("RefreshRatesJob exhausted all #{max_attempts} attempts. API is offline. Activating cool-down.")
        Api::V1::PricingService.cache_provider.activate_cool_down(COOL_DOWN_KEY, COOL_DOWN_DURATION)
        false
      end
    ensure
      Api::V1::PricingService.cache_provider.release_lock(lock_key)
    end
  end
end
