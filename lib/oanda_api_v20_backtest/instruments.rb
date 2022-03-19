# @see http://developer.oanda.com/rest-live-v20/instrument-ep/
module OandaApiV20Backtest
  module Instruments
    attr_reader :instrument, :granularity, :instrument_path

    # GET /v3/instruments/:instrument/candles
    def candles(options = {})
      # GET /v3/instruments/:instrument/candles
      # client.instrument('EUR_USD').candles(options).show
      count   = options[:count].to_i
      candles = all_candles(count).dup
      from    = 0
      to      = -1
      candles['candles'] = candles['candles'][from..to]
      candles
    end
  end
end
