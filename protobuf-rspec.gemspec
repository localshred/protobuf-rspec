# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "protobuf/rspec/version"

Gem::Specification.new do |s|
  s.name        = "protobuf-rspec"
  s.version     = Protobuf::RSpec::VERSION
  s.authors     = ["BJ Neilsen", "Adam Hutchison"]
  s.email       = ["bj.neilsen@gmail.com", "liveh2o@gmail.com"]
  s.homepage    = "http://github.com/localshred/protobuf-rspec"
  s.summary     = %q{Protobuf RSpec helpers for testing services and clients. Meant to be used with the protobuf gem. Decouple external services/clients from each other using the given helper methods.}
  s.description = s.summary

  s.rubyforge_project = "protobuf-rspec"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "protobuf", ">= 3.0.0"
  s.add_runtime_dependency "rspec", "~> 3.0"

  s.add_development_dependency "rake"
  s.add_development_dependency "yard", "~> 0.7"
  s.add_development_dependency "redcarpet", "~> 2.1"
end
