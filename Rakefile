require "rake/testtask"
require "bundler/gem_tasks"

task :default => :test

Rake::TestTask.new do |t|
  t.libs << 'lib' << 'test'
  t.test_files = Dir["test/**/*_test.rb"]
  t.verbose = true
end

task :submodules do
  if File.exist?(File.dirname(__FILE__) + "/.git")
    sh %{git submodule sync}
    sh %{git submodule update --init --recursive}
  end
end
