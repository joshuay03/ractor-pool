# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

namespace :rbs do
  task :generate do
    puts
    sh "rm -rf sig && rbs-inline --opt-out --output lib && echo"
  end
end

task build: :"rbs:generate"
task default: %i[rbs:generate test]
