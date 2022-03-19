module OandaApiV20Backtest
  class Position
    attr_accessor :options, :current_candle
    attr_reader   :position

    class << self
      def find_by_instrument(instrument)
        long_trades  = []
        short_trades = []

        $redis.smembers('backtest:active:trades').each do |id|
          trade = Trade.find(id)

          if trade.trade['trade']['instrument'] == instrument && trade.trade['trade']['state'] == 'OPEN'
            type = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short

            case type
            when :long
              long_trades << trade.trade['trade']
            when :short
              short_trades << trade.trade['trade']
            end
          end
        end

        redis_position = {
          'position' => {
            'instrument'   => instrument,
            'pl'           => '0.0000',
            'resettablePL' => '0.0000',
            'financing'    => '0.0000',
            'commission'   => '0.0000',
            'unrealizedPL' => '0.0000',
            'long'         => {
              'units'        => '0',
              'pl'           => '0.0000',
              'resettablePL' => '0.0000',
              'financing'    => '0.0000',
              'unrealizedPL' => '0.0000'
            },
            'short'        => {
              'units'        => '0',
              'pl'           => '0.0000',
              'resettablePL' => '0.0000',
              'financing'    => '0.0000',
              'unrealizedPL' => '0.0000'
            }
          }
        }

        if !long_trades.empty?
          total_units = 0
          total_price = 0.0

          long_trades.each do |trade|
            total_units += trade['currentUnits'].to_i
            total_price += trade['currentUnits'].to_f * trade['price'].to_f
          end

          redis_position['position']['long'].merge!(
            'averagePrice' => (total_price / total_units).round(5).to_s,
            'tradeIDs'     => long_trades.map{ |trade| trade['id'].to_s },
            'units'        => long_trades.map{ |trade| trade['currentUnits'].to_i }.inject(0){ |sum, units| sum + units }.to_s,
            'pl'           => ''
          )
        end

        if !short_trades.empty?
          total_units = 0
          total_price = 0.0

          short_trades.each do |trade|
            total_units += trade['currentUnits'].to_i
            total_price += trade['currentUnits'].to_f * trade['price'].to_f
          end

          redis_position['position']['short'].merge!(
            'averagePrice' => (total_price / total_units).round(5).to_s,
            'tradeIDs'     => short_trades.map{ |trade| trade['id'].to_s },
            'units'        => short_trades.map{ |trade| trade['currentUnits'].to_i }.inject(0){ |sum, units| sum + units }.to_s,
            'pl'           => ''
          )
        end

        Position.new(position: redis_position)
      end
    end

    def initialize(args = {})
      if args[:position]
        @position = args[:position]
        return
      end

      args.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      @options ||= {}
      @position = {}
    end
  end
end
