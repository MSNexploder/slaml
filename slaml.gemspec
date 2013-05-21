# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'slaml/version'

Gem::Specification.new do |gem|
  gem.name          = "slaml"
  gem.version       = Slaml::VERSION
  gem.authors       = ["Stefan Huber"]
  gem.email         = ["MSNexploder@gmail.com"]
  gem.description   = "An elegant, structured (X)HTML/XML templating engine."
  gem.summary       = "Haml on Temple"
  gem.homepage      = "https://github.com/MSNexploder/slaml"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency('temple', ['~> 0.6.5'])
  gem.add_runtime_dependency('tilt', ['~> 1.3', '>= 1.3.3'])

  gem.add_development_dependency('rake', ['~> 10.0.3'])
  gem.add_development_dependency('minitest', ['~> 5.0.1'])
end
