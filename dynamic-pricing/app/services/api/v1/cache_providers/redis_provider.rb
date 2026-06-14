module Api::V1::CacheProviders
  class RedisProvider < BaseProvider
    RATES_KEY = "dynamic_pricing:rates_map".freeze

    def initialize(redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      require 'redis'
      require 'connection_pool'
      @redis_url = redis_url
    end

    def read_rates
      client_pool.with do |client|
        raw = client.get(RATES_KEY)
        return nil if raw.nil?

        parsed = JSON.parse(raw)
        {
          rates: parsed['rates'],
          fetched_at: Time.zone.parse(parsed['fetched_at'])
        }
      end
    rescue => e
      Rails.logger.error("RedisProvider read_rates error: #{e.message}")
      nil
    end

    def write_rates(rates, ttl = nil, fetched_at: Time.current)
      payload = {
        rates: rates,
        fetched_at: fetched_at
      }.to_json

      expiration = ttl || ENV.fetch('CACHE_TTL_SECONDS', '3600').to_i
      client_pool.with do |client|
        # Set the key with a configurable Time-to-Live (TTL)
        client.set(RATES_KEY, payload, ex: expiration.to_i)
      end
      true
    rescue => e
      Rails.logger.error("RedisProvider write_rates error: #{e.message}")
      false
    end

    def acquire_lock(key, ttl)
      # SET key value NX PX (milliseconds)
      # nx: true makes it SET if Not Exists
      # px: sets expiry in milliseconds
      client_pool.with do |client|
        !!client.set(key, Time.current.to_s, nx: true, px: (ttl * 1000).to_i)
      end
    rescue => e
      Rails.logger.error("RedisProvider acquire_lock error: #{e.message}")
      false
    end

    def release_lock(key)
      client_pool.with do |client|
        client.del(key)
      end
      true
    rescue => e
      Rails.logger.error("RedisProvider release_lock error: #{e.message}")
      false
    end

    def lock_held?(key)
      client_pool.with do |client|
        !!client.exists?(key)
      end
    rescue => e
      Rails.logger.error("RedisProvider lock_held? error: #{e.message}")
      false
    end

    def cool_down_active?(key)
      client_pool.with do |client|
        !!client.exists?(key)
      end
    rescue => e
      Rails.logger.error("RedisProvider cool_down_active? error: #{e.message}")
      false
    end

    def activate_cool_down(key, duration)
      client_pool.with do |client|
        client.set(key, "true", px: (duration * 1000).to_i)
      end
      true
    rescue => e
      Rails.logger.error("RedisProvider activate_cool_down error: #{e.message}")
      false
    end

    def clear_cache
      client_pool.with do |client|
        client.del(RATES_KEY)
        client.del("dynamic_pricing:refresh_lock")
        client.del("dynamic_pricing:api_cool_down")
      end
      true
    rescue => e
      Rails.logger.error("RedisProvider clear_cache error: #{e.message}")
      false
    end

    private

    def client_pool
      @client_pool ||= ConnectionPool.new(size: ENV.fetch("REDIS_POOL_SIZE", "5").to_i, timeout: 5) do
        Redis.new(url: @redis_url)
      end
    end
  end
end
