class RateApiClient
  include HTTParty
  base_uri ENV.fetch('RATE_API_URL', 'http://localhost:8080')
  headers "Content-Type" => "application/json"
  headers 'token' => ENV.fetch('RATE_API_TOKEN', '04aa6f42aa03f220c2ae9a276cd68c62')
  default_timeout ENV.fetch('RATE_API_TIMEOUT_SECONDS', '3').to_f

  def self.get_rate(period:, hotel:, room:)
    get_rates([{ period: period, hotel: hotel, room: room }])
  end

  def self.get_rates(attributes)
    params = { attributes: attributes }.to_json
    self.post("/pricing", body: params)
  end
end
