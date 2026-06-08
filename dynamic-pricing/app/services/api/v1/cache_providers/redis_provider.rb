module Api::V1::CacheProviders
  class RedisProvider < BaseProvider
    RATES_KEY = "dynamic_pricing:rates_map".freeze

    def initialize(redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      require 'redis'
      @redis_url = redis_url
    end

    def read_rates
      raw = client.get(RATES_KEY)
      return nil if raw.nil?

      parsed = JSON.parse(raw)
      {
        rates: parsed['rates'],
        fetched_at: Time.zone.parse(parsed['fetched_at'])
      }
    rescue => e
      Rails.logger.error("RedisProvider read_rates error: #{e.message}")
      nil
    end

    def write_rates(rates)
      payload = {
        rates: rates,
        fetched_at: Time.current
      }.to_json

      client.set(RATES_KEY, payload)
      true
    rescue => e
      Rails.logger.error("RedisProvider write_rates error: #{e.message}")
      false
    end

    def acquire_lock(key, ttl)
      # SET key value NX PX (milliseconds)
      # nx: true makes it SET if Not Exists
      # px: sets expiry in milliseconds
      !!client.set(key, Time.current.to_s, nx: true, px: (ttl * 1000).to_i)
    rescue => e
      Rails.logger.error("RedisProvider acquire_lock error: #{e.message}")
      false
    end

    def release_lock(key)
      client.del(key)
      true
    rescue => e
      Rails.logger.error("RedisProvider release_lock error: #{e.message}")
      false
    end

    def lock_held?(key)
      !!client.exists?(key)
    rescue => e
      Rails.logger.error("RedisProvider lock_held? error: #{e.message}")
      false
    end

    def cool_down_active?(key)
      !!client.exists?(key)
    rescue => e
      Rails.logger.error("RedisProvider cool_down_active? error: #{e.message}")
      false
    end

    def activate_cool_down(key, duration)
      client.set(key, "true", px: (duration * 1000).to_i)
      true
    rescue => e
      Rails.logger.error("RedisProvider activate_cool_down error: #{e.message}")
      false
    end

    private

    def client
      @client ||= Redis.new(url: @redis_url)
    end
  end
end
