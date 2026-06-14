module Api::V1::CacheProviders
  class RailsCacheProvider < BaseProvider
    RATES_KEY = "dynamic_pricing:rates_map".freeze

    def read_rates
      Rails.cache.read(RATES_KEY)
    end

    def write_rates(rates, ttl = nil, fetched_at: Time.current)
      payload = {
        rates: rates,
        fetched_at: fetched_at
      }
      expiration = ttl || ENV.fetch('CACHE_TTL_SECONDS', '3600').to_i
      # Store for up to the configured TTL to prevent serving excessively stale rates during outages
      Rails.cache.write(RATES_KEY, payload, expires_in: expiration)
    end

    def acquire_lock(key, ttl)
      # Rails.cache.write with unless_exist: true acts as an atomic lock.
      # It returns true if it successfully writes the key (lock acquired).
      # Note: We cast the return value to a boolean to ensure standard API.
      !!Rails.cache.write(key, Time.current, expires_in: ttl, unless_exist: true)
    end

    def release_lock(key)
      Rails.cache.delete(key)
    end

    def lock_held?(key)
      !Rails.cache.read(key).nil?
    end

    def cool_down_active?(key)
      !Rails.cache.read(key).nil?
    end

    def activate_cool_down(key, duration)
      Rails.cache.write(key, true, expires_in: duration)
    end

    def clear_cache
      Rails.cache.delete(RATES_KEY)
      Rails.cache.delete("dynamic_pricing:refresh_lock")
      Rails.cache.delete("dynamic_pricing:api_cool_down")
    end
  end
end
