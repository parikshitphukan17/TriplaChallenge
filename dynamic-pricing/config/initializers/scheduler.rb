# Start a background scheduler thread if running in a Rails server environment (e.g. rails s, puma)
# We skip running this scheduler thread during test suite runs, db migrations, or console sessions.
Rails.application.config.after_initialize do
  if (defined?(Rails::Server) || $0.end_with?('puma') || ENV['START_SCHEDULER'] == 'true') && !Rails.env.test?
    Thread.new do
      # Add a short delay to let the server boot finish completely
      sleep 5.seconds

      Rails.logger.info("Dynamic Pricing Proxy background scheduler thread started.")
      loop do
        begin
          RefreshRatesJob.new.perform
        rescue => e
          Rails.logger.error("Dynamic Pricing Proxy background scheduler thread error: #{e.message}")
        end
        # Sleep for 4 minutes before the next refresh cycle
        sleep 4.minutes
      end
    end
  end
end
