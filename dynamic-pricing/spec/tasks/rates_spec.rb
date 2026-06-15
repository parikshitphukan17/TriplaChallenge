require 'rails_helper'
require 'rake'

RSpec.describe 'rates:refresh', type: :task do
  before :all do
    # Load the rake task file
    Rake.application.rake_require 'tasks/rates'
    # Ensure environment task is defined (Rake normally gets it from Rails)
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
  end

  before :each do
    Rake::Task['rates:refresh'].reenable
  end

  it 'successfully invokes RefreshRatesJob perform and completes' do
    expect_any_instance_of(RefreshRatesJob).to receive(:perform).and_return(true)
    
    # We expect calling invoke to execute without raising errors or exiting
    expect { Rake::Task['rates:refresh'].invoke }.not_to raise_error
  end

  it 'raises SystemExit with status 1 when RefreshRatesJob fails' do
    expect_any_instance_of(RefreshRatesJob).to receive(:perform).and_return(false)
    
    # Rake task calls exit(1) on failure, which throws a SystemExit error in Ruby
    expect { Rake::Task['rates:refresh'].invoke }.to raise_error(SystemExit) do |error|
      expect(error.status).to eq(1)
    end
  end
end
