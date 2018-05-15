# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ubiquity/wiredrive/version'

Gem::Specification.new do |spec|
  spec.name          = 'ubiquity-wiredrive'
  spec.version       = Ubiquity::Wiredrive::VERSION
  spec.authors       = ['John Whitson']
  spec.email         = ['john.whitson@gmail.com']
  spec.summary       = %q{A library and utilities for interacting with Wiredrive's API}
  spec.description   = %q{}
  spec.homepage      = 'https://www.github.com/XPlatform-Consulting/ubiquity-wiredrive'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_runtime_dependency 'multipart-post', '~> 2.0'

end
