require 'prometheus_exporter/client'
require 'prometheus_exporter/middleware'

# Setup global PrometheusExporter Client based on environment variable
collector_url = ENV.fetch('PROMETHEUS_COLLECTOR_URL', 'http://localhost:9394')
uri = URI.parse(collector_url)

PrometheusExporter::Client.default = PrometheusExporter::Client.new(
  host: uri.host,
  port: uri.port || 9394
)

# Unshift PrometheusExporter::Middleware to the top of the Rails middleware stack
# This automatically collects request metrics for all endpoints.
Rails.application.config.middleware.unshift PrometheusExporter::Middleware
