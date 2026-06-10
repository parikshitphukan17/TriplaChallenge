require 'opentelemetry/sdk'
require 'opentelemetry/instrumentation/rails'
require 'opentelemetry/instrumentation/net/http'
require 'opentelemetry/exporter/otlp'

# Initialize and configure the OpenTelemetry SDK
OpenTelemetry::SDK.configure do |c|
  # Set the service name for trace identification
  c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'dynamic-pricing-proxy')

  # Instrument standard Rails components (ActiveRecord, ActionPack, etc.)
  c.use 'OpenTelemetry::Instrumentation::Rails'

  # Instrument outgoing Net::HTTP requests (used by HTTParty under the hood)
  c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
end
