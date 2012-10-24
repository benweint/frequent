# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.authors       = ["Ben Weintraub"]
  gem.email         = ["benweint@gmail.com"]
  gem.description   = %q{Ruby method instrumentation demo}
  gem.summary       = %q{Ruby method instrumentation demo}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.test_files    = gem.files.grep(%r{^(spec)/})
  gem.name          = "frequent"
  gem.require_paths = ["lib"]
  gem.version       = '0.1'

  gem.add_development_dependency('rake')
  gem.add_development_dependency('minitest')
  gem.add_development_dependency('minitest-matchers')
end
