module Api::V1::CacheProviders
  class BaseProvider
    RATES_KEY = "dynamic_pricing:rates_map".freeze

    def read_rates
      raise NotImplementedError, "#{self.class} must implement read_rates"
    end

    def write_rates(rates, ttl = nil, fetched_at: Time.current)
      raise NotImplementedError, "#{self.class} must implement write_rates"
    end

    def acquire_lock(key, ttl)
      raise NotImplementedError, "#{self.class} must implement acquire_lock"
    end

    def release_lock(key)
      raise NotImplementedError, "#{self.class} must implement release_lock"
    end

    def lock_held?(key)
      raise NotImplementedError, "#{self.class} must implement lock_held?"
    end

    def cool_down_active?(key)
      raise NotImplementedError, "#{self.class} must implement cool_down_active?"
    end

    def activate_cool_down(key, duration)
      raise NotImplementedError, "#{self.class} must implement activate_cool_down"
    end

    def clear_cache
      raise NotImplementedError, "#{self.class} must implement clear_cache"
    end

    def cache_ttl(override_ttl = nil)
      override_ttl || ENV.fetch('CACHE_TTL_SECONDS', '3600').to_i
    end
  end
end
