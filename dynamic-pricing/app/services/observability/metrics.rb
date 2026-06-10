require 'prometheus_exporter/client'

module Observability
  class Metrics
    class << self
      def client
        @client ||= PrometheusExporter::Client.default
      end

      # 1. Cache request counter (labeled by status: hit/miss)
      def cache_requests_total
        @cache_requests_total ||= client.register(
          :counter,
          "cache_requests_total",
          "Total cache requests labeled by status (hit/miss)"
        )
      end

      # 2. Circuit breaker gauge (active = 1, inactive = 0)
      def circuit_breaker_active
        @circuit_breaker_active ||= client.register(
          :gauge,
          "upstream_circuit_breaker_active",
          "Gauge indicating if the circuit-breaker is active (1 = active, 0 = inactive)"
        )
      end

      # 3. Upstream retries count
      def upstream_retries_total
        @upstream_retries_total ||= client.register(
          :counter,
          "upstream_retries_total",
          "Total upstream API retry attempts"
        )
      end

      # 4. Upstream failures count labeled by reason (timeout, 5xx, connection_failed, etc.)
      def upstream_failures_total
        @upstream_failures_total ||= client.register(
          :counter,
          "upstream_failures_total",
          "Total external request failures categorized by reason"
        )
      end

      # 5. Client validation failure count labeled by field
      def validation_failures_total
        @validation_failures_total ||= client.register(
          :counter,
          "validation_failures_total",
          "Total client request validation failures labeled by field"
        )
      end

      # 6. Cold start wait duration (summary)
      def cold_start_wait_seconds
        @cold_start_wait_seconds ||= client.register(
          :summary,
          "cold_start_wait_seconds",
          "Duration in seconds spent spin-locking and blocking on cold start requests"
        )
      end

      # 7. Background job duration (summary)
      def active_job_duration_seconds
        @active_job_duration_seconds ||= client.register(
          :summary,
          "active_job_duration_seconds",
          "Duration in seconds spent executing background jobs"
        )
      end

      # 8. Background job failure count
      def active_job_failures_total
        @active_job_failures_total ||= client.register(
          :counter,
          "active_job_failures_total",
          "Background job failure counts"
        )
      end

      # Safe wrapper methods to prevent application crashes on telemetry service downtime

      def observe_cache_request(status)
        cache_requests_total.observe(1, status: status.to_s)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log cache request metric: #{e.message}")
      end

      def set_circuit_breaker(active)
        value = active ? 1 : 0
        circuit_breaker_active.observe(value)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log circuit breaker metric: #{e.message}")
      end

      def observe_upstream_retry
        upstream_retries_total.observe(1)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log upstream retry metric: #{e.message}")
      end

      def observe_upstream_failure(reason)
        upstream_failures_total.observe(1, reason: reason.to_s)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log upstream failure metric: #{e.message}")
      end

      def observe_validation_failure(field)
        validation_failures_total.observe(1, field: field.to_s)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log validation failure metric: #{e.message}")
      end

      def observe_cold_start_wait(duration)
        cold_start_wait_seconds.observe(duration.to_f)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log cold start duration metric: #{e.message}")
      end

      def observe_job_duration(duration)
        active_job_duration_seconds.observe(duration.to_f)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log job duration metric: #{e.message}")
      end

      def observe_job_failure
        active_job_failures_total.observe(1)
      rescue => e
        Rails.logger.warn("Telemetry Error: Failed to log job failure metric: #{e.message}")
      end
    end
  end
end
