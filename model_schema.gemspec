# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'model_schema/version'

Gem::Specification.new do |spec|
  spec.name = 'model_schema'
  spec.version = ModelSchema::VERSION
  spec.authors = ['Karthik Viswanathan']
  spec.email = ['karthik.ksv@gmail.com']

  spec.summary = %(Annotate a Sequel Model with its expected schema (columns/indexes).)
  spec.homepage = 'TODO'
  spec.license = 'MIT'

  spec.files = `git ls-files -z`.split("\x0").reject {|f| f.match(%r{^(test|spec|features)/})}
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) {|f| File.basename(f)}
  spec.require_paths = ['lib']

  spec.add_development_dependency('bundler', '~> 1.10')
  spec.add_development_dependency('rake', '~> 10.0')
  spec.add_development_dependency('minitest')
  spec.add_development_dependency('minitest-hooks')
  spec.add_development_dependency('pg')
  spec.add_development_dependency('pry')
  spec.add_development_dependency('awesome_print')

  spec.add_runtime_dependency('sequel')
end
