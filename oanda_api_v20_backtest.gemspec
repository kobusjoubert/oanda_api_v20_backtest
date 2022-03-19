lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'oanda_api_v20_backtest/version'
require 'time'

Gem::Specification.new do |s|
  s.name        = 'oanda_api_v20_backtest'
  s.version     = OandaApiV20Backtest::VERSION
  s.date        = Date.today.to_s
  s.authors     = ['Kobus Joubert']
  s.email       = ['kobus@translate3d.com']

  s.summary     = %q{Ruby Oanda REST API V20 Mock Backtesting Requests}
  s.description = %q{Ruby client that supports the Oanda REST API V20 methods mocking requests for backtesting.}
  s.homepage    = 'https://github.com/kobusjoubert/oanda_api_v20_backtest'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if s.respond_to?(:metadata)
    s.metadata['allowed_push_host'] = 'https://github.com'
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  s.required_ruby_version = '>= 2.3.0'

  s.add_dependency 'redis', '~> 3.3'

  s.add_development_dependency 'bundler', '~> 1.13'
  s.add_development_dependency 'byebug',  '~> 9.0'
  s.add_development_dependency 'rake',    '~> 10.0'
  s.add_development_dependency 'rspec',   '~> 3.4'

  s.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  s.require_paths = ['lib']
end
