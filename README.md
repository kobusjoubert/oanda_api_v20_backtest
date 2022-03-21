# OandaApiV20Backtest

Gem to mock web requests allowing for backtesting on local machine only.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'oanda_api_v20_backtest'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install oanda_api_v20_backtest

## Usage

Copy the candles to a folder named in this way {INSTRUMENT}_{GRANULARITY}. Example ~/Desktop/EUR_USD_M1

Change to a directory where you want to run the candle server from and clone the repository, or just change directory to where the gem is installed.

    cd ~/Desktop
    git clone git@github.com:kobusjoubert/oanda_api_v20_backtest.git oanda_api_v20_backtest

Change to the repository directory.

    cd oanda_api_v20_backtest

Open up a ruby console specifying the path to where the candle folder lives.

    CANDLE_PATH=~/Documents/Instruments irb

ENV Options

    CANDLE_PATH=~/Documents/Instruments
    LEVERAGE=100:1
    INITIAL_BALANCE=10_000
    MARGIN_CLOSEOUT_ON_INITIAL_BALANCE=true

Start the candle server.

    require 'oanda_api_v20_backtest'
    DRb.start_service(OandaApiV20Backtest::CandleServer::URI, OandaApiV20Backtest::CandleServer.new(instrument: 'EUR_USD', granularity: 'M1'))
    DRb.thread.join

## Redis Keys

Keys used for backtesting:

    backtest:trade:1 = '{}'
    backtest:order:1 = '{}'
    backtest:transaction:1 = '{}'

    backtest:active:trades = []
    backtest:active:orders = []
    backtest:transactions = []

    backtest:last_transaction_id = '1'
    backtest:last_backtest_time = unixtime

    backtest:margin_closeout_trades = []

    backtest:spread:total = '100.00'

    backtest:balance = '10000.0000'

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kobusjoubert/oanda_api_v20_backtest.
