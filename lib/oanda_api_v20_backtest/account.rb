module OandaApiV20Backtest
  class Account
    ACCOUNT_ID = '000-000-000000-001'.freeze

    attr_accessor :id
    attr_reader :account

    class << self
      def find(id)
        # account = {
        #   'account' => {
        #     'id' => id
        #   }
        # }
        # Account.new(account: account)
        Account.new(id: id)
      end
    end

    def initialize(args = {})
      # if args[:account]
      #   @account = args[:account]
      #   @id      = @account['account']['id']
      #   return
      # end

      args.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      account_id = ACCOUNT_ID
      account_id = id if id && id != ''

      @account = {
        'account' => {
          'id' => account_id,
          'currency' => 'USD',
          'alias' => 'Backtesting!',
          'balance' => balance,
          'NAV' => '0.0000',
          'pl' => '0.0000',
          'resettablePL' => '0.0000',
          'financing' => '0.0000',
          'commission' => '0.0000',
          'guaranteedExecutionFees' => '0.0000',
          'unrealizedPL' => '0.0000',
          'marginUsed' => '0.0000',
          'marginAvailable' => '0.0000',
          'positionValue' => '0.0000',
          'marginCloseoutUnrealizedPL' => '0.0000',
          'marginCloseoutNAV' => '0.0000',
          'marginCloseoutMarginUsed' => '0.0000',
          'marginCloseoutPositionValue' => '0.0000',
          'marginCallMarginUsed' => '0.0000',
          'withdrawalLimit' => '0.0000',
          'marginCloseoutPercent' => '0.00000',
          'marginCallPercent' => '0.00000',
          'marginRate' => leverage.to_s, # Leverage of 100:1 = 0.01, 10:1 = 0.1 & 1:1 = 1
          'hedgingEnabled' => false,
          'openTradeCount' => 0,
          'openPositionCount' => 0,
          'pendingOrderCount' => 0,
          'resettablePLTime' => '2016-06-16T01:00:00.000000000Z'
        }
      }

      @id = @account['account']['id']
    end

    def leverage
      if ENV['LEVERAGE']
        leverage = ENV['LEVERAGE'].to_s
        return leverage.to_f unless leverage.include?(':')
        leverage = leverage.split(':')
        return leverage[1].to_f / leverage[0].to_f
      end

      return LEVERAGE
    end

    def initial_balance
      return ENV['INITIAL_BALANCE'].to_f if ENV['INITIAL_BALANCE']
      return INITIAL_BALANCE
    end

    def balance
      current_redis_balance = $redis.get('backtest:balance')
      return current_redis_balance.to_f.round(4) if current_redis_balance
      return initial_balance
    end

    def balance=(value)
      $redis.set('backtest:balance', value.round(4))
    end
  end
end
