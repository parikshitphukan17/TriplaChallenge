Rails.application.configure do
  # Enable lograge for structured single-line JSON logging
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  # Append custom options to the log payloads
  config.lograge.custom_options = lambda do |event|
    options = {
      time: Time.current.iso8601,
      request_id: event.payload[:headers]["action_dispatch.request_id"],
      params: event.payload[:params].except("controller", "action")
    }

    # Append OpenTelemetry trace details if available
    if defined?(OpenTelemetry)
      current_span = OpenTelemetry::Trace.current_span
      if current_span && current_span.context.valid?
        options[:trace_id] = current_span.context.hex_trace_id
        options[:span_id] = current_span.context.hex_span_id
      end
    end

    options
  end
end
