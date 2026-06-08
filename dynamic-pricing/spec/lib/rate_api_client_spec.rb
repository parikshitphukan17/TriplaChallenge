require 'rails_helper'
require 'rate_api_client'

RSpec.describe RateApiClient do
  describe 'default_timeout' do
    after do
      ENV.delete('RATE_API_TIMEOUT_SECONDS')
      load Rails.root.join('lib/rate_api_client.rb')
    end

    it 'defaults to 3 seconds' do
      ENV.delete('RATE_API_TIMEOUT_SECONDS')
      load Rails.root.join('lib/rate_api_client.rb')
      expect(RateApiClient.default_options[:timeout]).to eq(3.0)
    end

    it 'uses RATE_API_TIMEOUT_SECONDS when set' do
      ENV['RATE_API_TIMEOUT_SECONDS'] = '5.5'
      load Rails.root.join('lib/rate_api_client.rb')
      expect(RateApiClient.default_options[:timeout]).to eq(5.5)
    end
  end
end
