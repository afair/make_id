# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

task default: %i[spec standard]

desc "Open and IRB Console with the gem loaded"
task :console do
  sh "bundle exec irb  -Ilib -I . -r make_id"
end
