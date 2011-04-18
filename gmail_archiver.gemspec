# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "gmail_archiver/version"

Gem::Specification.new do |s|
  s.name        = "gmail_archiver"
  s.version     = GmailArchiver::VERSION
  s.platform    = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.0'

  s.authors     = ["Daniel Choi"]
  s.email       = ["dhchoi@gmail.com"]
  # s.homepage    = "http://danielchoi.com/software/gmail_archiver.html"
  s.summary     = %q{Archive your Gmail to PostgreSQL}
  s.description = %q{Move stuff off your Gmail account}

  s.rubyforge_project = "gmail_archiver"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'mail', '>= 2.2.12'
  s.add_dependency 'highline', '>= 1.6.1'
end
