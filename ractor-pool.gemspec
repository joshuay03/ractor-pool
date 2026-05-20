# frozen_string_literal: true

require_relative "lib/ractor-pool/version"

Gem::Specification.new do |spec|
  spec.name = "ractor-pool"
  spec.version = RactorPool::VERSION
  spec.authors = ["Joshua Young"]
  spec.email = ["djry1999@gmail.com"]

  spec.summary = "A thread-safe, lock-free pool of Ractor workers with coordinator or round-robin dispatch for distributing work"
  spec.homepage = "https://github.com/joshuay03/ractor-pool"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) || f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "warning"
  spec.add_dependency "atomic-ruby"
end
