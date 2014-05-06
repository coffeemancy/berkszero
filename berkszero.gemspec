# coding: utf-8
lib = ::File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "berkszero/version"
require "English"

Gem::Specification.new do |spec|
  spec.name          = "berkszero"
  spec.version       = BerksZero::VERSION
  spec.authors       = ["Carlton Stedman"]
  spec.email         = ["n/a"]
  spec.description   = "Spins up easy-to-use Chef-Zero/Berkshelf locally"
  spec.summary       = "Spins up easy-to-use Chef-Zero/Berkshelf locally"
  spec.homepage      = ""
  spec.license       = "DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE"

  spec.files         = `git ls-files`.split($RS)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| ::File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"

  # runtime dependencies
  spec.add_runtime_dependency "chef-zero", "~> 2.0"
end
