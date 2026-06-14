require 'rails_helper'

RSpec.describe Api::V1::CacheProviders::RailsCacheProvider do
  before do
    @old_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear
  end

  after do
    Rails.cache = @old_cache
  end

  subject { described_class.new }

  describe '#write_rates' do
    it 'writes rates with 1-hour expiration by default' do
      rates = { 'Summer:FloatingPointResort:SingletonRoom' => '12345' }

      expect(Rails.cache).to receive(:write).with(
        'dynamic_pricing:rates_map',
        hash_including(rates: rates),
        expires_in: 3600
      )

      subject.write_rates(rates)
    end

    it 'respects the explicit ttl parameter' do
      rates = { 'Summer:FloatingPointResort:SingletonRoom' => '12345' }

      expect(Rails.cache).to receive(:write).with(
        'dynamic_pricing:rates_map',
        hash_including(rates: rates),
        expires_in: 1800
      )

      subject.write_rates(rates, 1800)
    end

    it 'respects CACHE_TTL_SECONDS environment variable if set' do
      rates = { 'Summer:FloatingPointResort:SingletonRoom' => '12345' }
      stub_const('ENV', ENV.to_h.merge('CACHE_TTL_SECONDS' => '7200'))

      expect(Rails.cache).to receive(:write).with(
        'dynamic_pricing:rates_map',
        hash_including(rates: rates),
        expires_in: 7200
      )

      subject.write_rates(rates)
    end
  end
end
