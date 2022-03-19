module OandaApiV20Backtest
  class Trade
    attr_accessor :id, :time, :options, :current_candle
    attr_reader   :trade

    class << self
      def find(id)
        raise(OandaApiV20Backtest::NotFound, "Trade #{id} does not exist!") unless $redis.exists("backtest:trade:#{id.to_i}")
        redis_trade = JSON.parse($redis.get("backtest:trade:#{id.to_i}"))
        Trade.new(trade: redis_trade)
      end
    end

    def initialize(args = {})
      if args[:trade]
        @trade = args[:trade]
        @id    = @trade['trade']['id']
        return
      end

      args.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      @options ||= {}

      @trade = {
        'trade' => {
          'id'                    => id.to_s,
          'instrument'            => options['order']['instrument'],
          'price'                 => price_on_enter(current_candle, options).to_s,
          'initialUnits'          => options['order']['units'],
          'currentUnits'          => options['order']['units'],
          'initialMarginRequired' => '0.0000',
          'financing'             => '0.0000',
          'realizedPL'            => '0.0000',
          'unrealizedPL'          => '0.0000',
          'openTime'              => time,
          'state'                 => 'OPEN'
        }
      }
    end

    def save
      account = Account.new

      $redis.sadd('backtest:active:trades', id) if trade['trade']['state'] == 'OPEN'
      $redis.srem('backtest:active:trades', id) if trade['trade']['state'] == 'CLOSED' # 'CLOSE_WHEN_TRADEABLE'

      $redis.set("backtest:trade:#{id}", trade.to_json)

      if trade['trade']['state'] == 'CLOSED'
        new_balance     = account.balance + trade['trade']['realizedPL'].to_f
        account.balance = new_balance
      end
    end

    private

    def price_on_enter(current_candle, options)
      return options['order']['price'].to_f if options['order']['price']

      trigger_price = TRIGGER_CONDITION[options['order']['triggerCondition']]
      trigger_price = TRIGGER_CONDITION['DEFAULT'] unless trigger_price
      type          = options['order']['units'].to_f > 0 ? :long : :short

      current_candle[trigger_price[type]]['c'].to_f
    end
  end
end
