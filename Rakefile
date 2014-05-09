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
### Determine which spec tests to run
#
# Without this, due to RSpec funny business, when a pattern is missing, will
# default to running all tests, which chokes on any serverspec files.
#
specs = %w{ rspec }.select { |s| ::File.exist?("spec/#{s}") }

namespace :unit do
  begin
    require "rspec/core/rake_task"

    specs.each do |spec_type|
      desc "Run #{spec_type} checks"
      RSpec::Core::RakeTask.new(spec_type.to_sym) do |t|
        t.pattern = "spec/#{spec_type}/*_spec.rb"
        t.rspec_opts = [].tap do |a|
          a.push("--color")
          a.push("--format documentation")
        end.join(" ")
      end
    end
  rescue LoadError
    "#{$ERROR_INFO} -- spec tasks not loaded!"
  end
end

desc "Run all unit tests"
task :unit => specs.map { |s| "unit:#{s}" }

# The default rake task
task :default => %w{ style unit }
