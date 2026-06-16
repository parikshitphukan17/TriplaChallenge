module Api::V1::CacheProviders
  class RailsCacheProvider < BaseProvider
    def read_rates
      Rails.cache.read(RATES_KEY)
    end

    def write_rates(rates, ttl = nil, fetched_at: Time.current)
      payload = {
        rates: rates,
        fetched_at: fetched_at
      }
      expiration = cache_ttl(ttl)
      # Store for up to the configured TTL to prevent serving excessively stale rates during outages
      Rails.cache.write(RATES_KEY, payload, expires_in: expiration)
    end

    def acquire_lock(key, ttl)
      # FileStore and MemoryStore do not honour the `unless_exist:` option atomically —
      # `write` always returns true regardless of whether the key existed.
      # We use a process-level Mutex to make this safe for single-process (single-pod)
      # environments. For multi-pod deployments, switch to RedisProvider which uses
      # Redis SET NX for true distributed atomic locking.
      lock_mutex.synchronize do
        return false if Rails.cache.exist?(key)
        Rails.cache.write(key, Time.current, expires_in: ttl)
        true
      end
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
    private

    def lock_mutex
      @lock_mutex ||= Mutex.new
    end
  end
end
