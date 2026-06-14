require 'rails_helper'

RSpec.describe RefreshRatesJob, type: :job do
  before do
    @old_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear
  end

  after do
    Rails.cache = @old_cache
  end

  describe '#perform' do
    let(:job) { RefreshRatesJob.new }

    context 'when the upstream API fails' do
      before do
        allow(RateApiClient).to receive(:get_rates).and_return(
          OpenStruct.new(success?: false, code: 500, body: 'Upstream Failure')
        )
      end

      it 'retries 3 times with exponential backoff and random jitter' do
        sleep_times = []
        allow(job).to receive(:sleep) do |time|
          sleep_times << time
        end

        expect(job.perform).to be false

        expect(sleep_times.size).to eq(2)
        # Attempt 1 failed: backoff_base = 2, range should be 0.0..2.0
        expect(sleep_times[0]).to be_between(0.0, 2.0)
        # Attempt 2 failed: backoff_base = 4, range should be 0.0..4.0
        expect(sleep_times[1]).to be_between(0.0, 4.0)

        # Verify cool-down is activated
        expect(Api::V1::PricingService.cache_provider.cool_down_active?(RefreshRatesJob::COOL_DOWN_KEY)).to be true
      end
    end
  end
end
