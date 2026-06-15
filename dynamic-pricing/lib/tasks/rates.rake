namespace :rates do
  desc "Refresh cached dynamic pricing rates from upstream API"
  task refresh: :environment do
    Rails.logger.info("Rake task rates:refresh started.")
    begin
      success = RefreshRatesJob.new.perform
      if success
        Rails.logger.info("Rake task rates:refresh completed successfully.")
      else
        Rails.logger.error("Rake task rates:refresh failed.")
        exit(1)
      end
    ensure
      if defined?(PrometheusExporter::Client) && PrometheusExporter::Client.default
        PrometheusExporter::Client.default.stop(wait_timeout_seconds: 5)
      end
    end
  end
end
