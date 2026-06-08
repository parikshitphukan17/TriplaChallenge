module Api::V1::CacheProviders
  class RailsCacheProvider < BaseProvider
    RATES_KEY = "dynamic_pricing:rates_map".freeze

    def read_rates
      Rails.cache.read(RATES_KEY)
    end

    def write_rates(rates)
      payload = {
        rates: rates,
        fetched_at: Time.current
      }
      # Store indefinitely to allow stale rate serving if upstream is down
      Rails.cache.write(RATES_KEY, payload)
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
  end
end
