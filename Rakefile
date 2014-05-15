# encoding: UTF-8

require "bundler/setup"
require "English"

require "bundler/gem_tasks"

## Style checking
#
namespace :style do
  begin
    require "rubocop/rake_task"
    desc "Run Ruby style checks"
    Rubocop::RakeTask.new(:ruby)
  rescue LoadError
    "#{$ERROR_INFO} -- rubocop tasks not loaded!"
  end
end

desc "Run all style checks"
task :style => %w{ style:ruby }

## Unit tests
#
namespace :unit do
  begin
    require "rspec/core/rake_task"

    desc "Run rspec checks"
    RSpec::Core::RakeTask.new(:rspec) do |t|
      t.pattern = "spec/*_spec.rb"
      t.rspec_opts = "--color --format documentation"
    end
  rescue LoadError
    "#{$ERROR_INFO} -- spec tasks not loaded!"
  end
end

desc "Run all unit tests"
task :unit => %w{ unit:rspec }

# The default rake task
task :default => %w{ style unit }
