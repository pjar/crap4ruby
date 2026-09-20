# frozen_string_literal: true

SimpleCov.configure do
  command_name "Unit Tests"
  enable_coverage :branch
  enable_coverage :method
  merge_subprocesses true
  cover "lib/**/*.rb"
end
