namespace :rates do
  desc "Refresh cached dynamic pricing rates from upstream API"
  task refresh: :environment do
    Rails.logger.info("Rake task rates:refresh started.")
    success = RefreshRatesJob.new.perform
    if success
      Rails.logger.info("Rake task rates:refresh completed successfully.")
    else
      Rails.logger.error("Rake task rates:refresh failed.")
      exit(1)
    end
  end
end
