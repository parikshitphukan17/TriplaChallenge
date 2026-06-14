require 'rails_helper'

RSpec.describe Api::V1::CacheProviders::RedisProvider do
  let(:redis_url) { 'redis://localhost:6379/9' }
  let(:mock_redis) { double('Redis') }

  before do
    allow(Redis).to receive(:new).with(url: redis_url).and_return(mock_redis)
  end

  subject { described_class.new(redis_url) }

  describe '#write_rates' do
    it 'serializes the payload and writes to Redis with a 1-hour expiration (3600 seconds) by default' do
      rates = { 'Summer:FloatingPointResort:SingletonRoom' => '12345' }

      expect(mock_redis).to receive(:set).with(
        'dynamic_pricing:rates_map',
        anything,
        ex: 3600
      ).and_return('OK')

      expect(subject.write_rates(rates)).to be true
    end

    it 'respects the explicit ttl parameter' do
      rates = { 'Summer:FloatingPointResort:SingletonRoom' => '12345' }

      expect(mock_redis).to receive(:set).with(
        'dynamic_pricing:rates_map',
        anything,
        ex: 1800
      ).and_return('OK')

      expect(subject.write_rates(rates, 1800)).to be true
    end

    it 'respects CACHE_TTL_SECONDS environment variable if set' do
      rates = { 'Summer:FloatingPointResort:SingletonRoom' => '12345' }
      stub_const('ENV', ENV.to_h.merge('CACHE_TTL_SECONDS' => '7200'))

      expect(mock_redis).to receive(:set).with(
        'dynamic_pricing:rates_map',
        anything,
        ex: 7200
      ).and_return('OK')

      expect(subject.write_rates(rates)).to be true
    end
  end

  describe '#read_rates' do
    it 'returns parsed rates and fetched_at time' do
      payload = {
        rates: { 'Summer:FloatingPointResort:SingletonRoom' => '12345' },
        fetched_at: Time.current.iso8601
      }.to_json

      expect(mock_redis).to receive(:get).with('dynamic_pricing:rates_map').and_return(payload)

      result = subject.read_rates
      expect(result[:rates]).to eq({ 'Summer:FloatingPointResort:SingletonRoom' => '12345' })
      expect(result[:fetched_at]).to be_a(ActiveSupport::TimeWithZone)
    end

    it 'returns nil if key does not exist' do
      expect(mock_redis).to receive(:get).with('dynamic_pricing:rates_map').and_return(nil)
      expect(subject.read_rates).to be_nil
    end
  end

  describe '#acquire_lock' do
    it 'acquires lock via SET NX PX' do
      expect(mock_redis).to receive(:set).with(
        'refresh_lock',
        anything,
        nx: true,
        px: 120000
      ).and_return(true)

      expect(subject.acquire_lock('refresh_lock', 2.minutes)).to be true
    end
  end

  describe '#release_lock' do
    it 'deletes lock key' do
      expect(mock_redis).to receive(:del).with('refresh_lock').and_return(1)
      expect(subject.release_lock('refresh_lock')).to be true
    end
  end
end
