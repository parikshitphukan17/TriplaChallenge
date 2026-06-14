require 'swagger_helper'

RSpec.describe 'api/v1/pricing', type: :request do
  before(:all) do
    if ENV['CACHE_PROVIDER_TYPE'] == 'rails_cache'
      @old_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end
  end

  after(:all) do
    if ENV['CACHE_PROVIDER_TYPE'] == 'rails_cache'
      Rails.cache = @old_cache
    end
  end

  before(:each) do
    Api::V1::PricingService.cache_provider.clear_cache
  end

  path '/api/v1/pricing' do
    get 'Retrieves pricing rate' do
      tags 'Pricing'
      produces 'application/json'
      parameter name: :period, in: :query, type: :string, description: 'Season period (Summer, Autumn, Winter, Spring)', required: true
      parameter name: :hotel, in: :query, type: :string, description: 'Hotel name (FloatingPointResort, GitawayHotel, RecursionRetreat)', required: true
      parameter name: :room, in: :query, type: :string, description: 'Room type (SingletonRoom, BooleanTwin, RestfulKing)', required: true

      response '200', 'Pricing rate successfully retrieved (Supports both fresh rates and stale fallback with disclaimer).

### Success Scenarios

#### 1. Fresh Rate (No Disclaimer)
Returned when the rate is fetched within the 5-minute validity window.
```json
{
  "resultInfo": {
    "code": "S",
    "message": "Success",
    "codeId": "1"
  },
  "data": {
    "rate": 15000,
    "disclaimer": null
  }
}
```

#### 2. Stale Rate Fallback (With Warning Disclaimer)
Served when the rate is older than 5 minutes due to upstream API downtime or synchronous fetch locks.
```json
{
  "resultInfo": {
    "code": "S",
    "message": "Success",
    "codeId": "1"
  },
  "data": {
    "rate": 15000,
    "disclaimer": "Rates are expired, please retry again in at least 5 minutes to get latest rate"
  }
}
```' do
        examples 'application/json' => {
          'Fresh Rate (Default)' => {
            summary: 'A fresh rate retrieved from the cache within the 5-minute validity window.',
            value: {
              resultInfo: { code: 'S', message: 'Success', codeId: '1' },
              data: { rate: 15000, disclaimer: nil }
            }
          },
          'Stale Rate Fallback' => {
            summary: 'A stale rate served as a fallback due to upstream API downtime or synchronous locks.',
            value: {
              resultInfo: { code: 'S', message: 'Success', codeId: '1' },
              data: { rate: 15000, disclaimer: 'Rates are expired, please retry again in at least 5 minutes to get latest rate' }
            }
          }
        }

        schema type: :object,
          properties: {
            resultInfo: {
              type: :object,
              properties: {
                code: { type: :string, example: 'S' },
                message: { type: :string, example: 'Success' },
                codeId: { type: :string, example: '1' }
              },
              required: %w[code message codeId]
            },
            data: {
              type: :object,
              properties: {
                rate: { type: :integer, description: 'The current rate value', example: 15000 },
                disclaimer: { 
                  type: :string, 
                  description: 'Warning notice. Present only when the served rate is stale (older than 5 minutes) due to upstream API downtime or synchronous fetch locks. Omitted (null) when the rate is fresh.',
                  example: 'Rates are expired, please retry again in at least 5 minutes to get latest rate', 
                  nullable: true 
                }
              },
              required: %w[rate]
            }
          },
          required: %w[resultInfo data]

        let(:period) { 'Summer' }
        let(:hotel) { 'FloatingPointResort' }
        let(:room) { 'SingletonRoom' }

        before do
          rates_data = { "Summer:FloatingPointResort:SingletonRoom" => 15000 }
          Api::V1::PricingService.cache_provider.write_rates(rates_data)
        end

        run_test!
      end

      response '400', 'Invalid Parameters' do
        schema type: :object,
          properties: {
            resultInfo: {
              type: :object,
              properties: {
                code: { type: :string, example: 'F' },
                message: { type: :string, example: 'Invalid period. Must be one of: Summer, Autumn, Winter, Spring' },
                codeId: { type: :string, example: 'INVALID_PARAMETERS' }
              },
              required: %w[code message codeId]
            },
            data: { type: :null }
          },
          required: %w[resultInfo]

        let(:period) { 'invalid-period' }
        let(:hotel) { 'FloatingPointResort' }
        let(:room) { 'SingletonRoom' }

        run_test!
      end

      response '404', 'Rate Not Found' do
        schema type: :object,
          properties: {
            resultInfo: {
              type: :object,
              properties: {
                code: { type: :string, example: 'F' },
                message: { type: :string, example: 'Rate not found for the requested parameters.' },
                codeId: { type: :string, example: 'RATE_NOT_FOUND' }
              },
              required: %w[code message codeId]
            },
            data: { type: :null }
          },
          required: %w[resultInfo]

        let(:period) { 'Summer' }
        let(:hotel) { 'FloatingPointResort' }
        let(:room) { 'SingletonRoom' }

        before do
          # Cache rates map exists but does not contain our key
          rates_data = { "Summer:FloatingPointResort:BooleanTwin" => 55555 }
          Api::V1::PricingService.cache_provider.write_rates(rates_data)
        end

        run_test!
      end

      response '503', 'Service Unavailable (Cold Start Outage)' do
        schema type: :object,
          properties: {
            resultInfo: {
              type: :object,
              properties: {
                code: { type: :string, example: 'F' },
                message: { type: :string, example: 'Rates are unavailable and cache is empty. Please retry in 5 minutes.' },
                codeId: { type: :string, example: 'SERVICE_UNAVAILABLE' }
              },
              required: %w[code message codeId]
            },
            data: { type: :null }
          },
          required: %w[resultInfo]

        let(:period) { 'Summer' }
        let(:hotel) { 'FloatingPointResort' }
        let(:room) { 'SingletonRoom' }

        before do
          Api::V1::PricingService.cache_provider.clear_cache
          # Stub the sync refresh to fail so it returns 503
          allow_any_instance_of(RefreshRatesJob).to receive(:perform).and_return(false)
        end

        run_test!
      end

      response '500', 'Internal Server Error' do
        schema type: :object,
          properties: {
            resultInfo: {
              type: :object,
              properties: {
                code: { type: :string, example: 'F' },
                message: { type: :string, example: 'An unexpected error occurred: Database connection lost' },
                codeId: { type: :string, example: 'INTERNAL_SERVER_ERROR' }
              },
              required: %w[code message codeId]
            },
            data: { type: :null }
          },
          required: %w[resultInfo]

        let(:period) { 'Summer' }
        let(:hotel) { 'FloatingPointResort' }
        let(:room) { 'SingletonRoom' }

        before do
          allow(Api::V1::PricingService).to receive(:new).and_raise("Database connection lost")
        end

        run_test!
      end
    end
  end

  describe 'GET /api/v1/pricing unhandled exceptions' do
    it 'returns internal server error (HTTP 500) on unhandled exception' do
      allow(Api::V1::PricingService).to receive(:new).and_raise("Database connection lost")

      get '/api/v1/pricing', params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      expect(response).to have_http_status(:internal_server_error)
      json_response = JSON.parse(response.body)
      expect(json_response.dig("resultInfo", "code")).to eq("F")
      expect(json_response.dig("resultInfo", "codeId")).to eq("INTERNAL_SERVER_ERROR")
      expect(json_response.dig("resultInfo", "message")).to include("Database connection lost")
      expect(json_response["data"]).to be_nil
    end
  end
end
