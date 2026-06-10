require 'rails_helper'

RSpec.describe Observability::Metrics do
  let(:mock_metric) { double('Metric', observe: nil) }

  before do
    # Reset internal class variables to force re-registration
    Observability::Metrics.instance_variable_set(:@cache_requests_total, nil)
    Observability::Metrics.instance_variable_set(:@circuit_breaker_active, nil)
    Observability::Metrics.instance_variable_set(:@upstream_retries_total, nil)
    Observability::Metrics.instance_variable_set(:@upstream_failures_total, nil)
    Observability::Metrics.instance_variable_set(:@validation_failures_total, nil)
    Observability::Metrics.instance_variable_set(:@cold_start_wait_seconds, nil)
    Observability::Metrics.instance_variable_set(:@active_job_duration_seconds, nil)
    Observability::Metrics.instance_variable_set(:@active_job_failures_total, nil)

    allow(PrometheusExporter::Client.default).to receive(:register).and_return(mock_metric)
  end

  describe '.observe_cache_request' do
    it 'registers the counter and records hit status' do
      expect(PrometheusExporter::Client.default).to receive(:register).with(
        :counter, "cache_requests_total", anything
      ).and_return(mock_metric)
      expect(mock_metric).to receive(:observe).with(1, status: "hit")

      Observability::Metrics.observe_cache_request(:hit)
    end
  end

  describe '.set_circuit_breaker' do
    it 'registers the gauge and sets active state to 1' do
      expect(PrometheusExporter::Client.default).to receive(:register).with(
        :gauge, "upstream_circuit_breaker_active", anything
      ).and_return(mock_metric)
      expect(mock_metric).to receive(:observe).with(1)

      Observability::Metrics.set_circuit_breaker(true)
    end

    it 'registers the gauge and sets inactive state to 0' do
      expect(PrometheusExporter::Client.default).to receive(:register).with(
        :gauge, "upstream_circuit_breaker_active", anything
      ).and_return(mock_metric)
      expect(mock_metric).to receive(:observe).with(0)

      Observability::Metrics.set_circuit_breaker(false)
    end
  end

  describe '.observe_upstream_failure' do
    it 'registers the failure counter and records reason' do
      expect(PrometheusExporter::Client.default).to receive(:register).with(
        :counter, "upstream_failures_total", anything
      ).and_return(mock_metric)
      expect(mock_metric).to receive(:observe).with(1, reason: "timeout")

      Observability::Metrics.observe_upstream_failure("timeout")
    end
  end

  describe '.observe_validation_failure' do
    it 'registers the validation counter and records field name' do
      expect(PrometheusExporter::Client.default).to receive(:register).with(
        :counter, "validation_failures_total", anything
      ).and_return(mock_metric)
      expect(mock_metric).to receive(:observe).with(1, field: "period")

      Observability::Metrics.observe_validation_failure("period")
    end
  end
end
