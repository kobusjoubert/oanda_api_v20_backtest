module OandaApiV20Backtest
  class Order
    attr_accessor :id, :time, :trade_id, :type, :options
    attr_reader   :order

    class << self
      def find(id)
        raise OandaApiV20Backtest::NotFound, "Order #{id} does not exist!" unless $redis.exists("backtest:order:#{id.to_i}")
        redis_order = JSON.parse($redis.get("backtest:order:#{id.to_i}"))
        Order.new(order: redis_order)
      end
    end

    def initialize(args = {})
      if args[:order]
        @order = args[:order]
        @id    = @order['order']['id']
        return
      end

      args.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      @options ||= {}

      @order = {
        'order' => {
          'type'       => type,
          'id'         => id.to_s,
          'createTime' => time,
          'state'      => 'PENDING'
        }
      }

      if options['takeProfit'] && type == 'TAKE_PROFIT'
        @order['order'].merge!(
          'tradeID'          => trade_id.to_s,
          'triggerCondition' => options['takeProfit']['triggerCondition'] || 'DEFAULT', # 'TRIGGER_DEFAULT'?
          'timeInForce'      => options['takeProfit']['timeInForce'] || 'GTC',
          'price'            => options['takeProfit']['price'].to_s
        )
      end

      if options['stopLoss'] && type == 'STOP_LOSS'
        @order['order'].merge!(
          'tradeID'          => trade_id.to_s,
          'triggerCondition' => options['stopLoss']['triggerCondition'] || 'DEFAULT', # 'TRIGGER_DEFAULT'?
          'timeInForce'      => options['stopLoss']['timeInForce'] || 'GTC',
          'price'            => options['stopLoss']['price'].to_s
        )
      end

      if options['trailingStopLoss'] && type == 'TRAILING_STOP_LOSS'
        @order['order'].merge!(
          'tradeID'          => trade_id.to_s,
          'triggerCondition' => options['trailingStopLoss']['triggerCondition'] || 'DEFAULT', # 'TRIGGER_DEFAULT'?
          'timeInForce'      => options['trailingStopLoss']['timeInForce'] || 'GTC',
          'price'            => options['trailingStopLoss']['price'].to_s
        )
      end

      if options['order']
        @order['order']['timeInForce'] = options['order']['timeInForce'] || 'GTC'

        if options['order']['instrument']
          @order['order']['instrument'] = options['order']['instrument']
        end

        if options['order']['units']
          @order['order']['units'] = options['order']['units']
        end

        if options['order']['price']
          @order['order']['price'] = options['order']['price']
        end

        if options['order']['priceBound']
          @order['order']['priceBound'] = options['order']['priceBound']
        end

        if options['order']['takeProfitOnFill']
          @order['order']['takeProfitOnFill'] = options['order']['takeProfitOnFill']
        end

        if options['order']['stopLossOnFill']
          @order['order']['stopLossOnFill'] = options['order']['stopLossOnFill']
        end

        if options['order']['trailingStopLossOnFill']
          @order['order']['trailingStopLossOnFill'] = options['order']['trailingStopLossOnFill']
        end

        if options['order']['gtdTime']
          @order['order']['gtdTime'] = options['order']['gtdTime']
        end

        if options['order']['tradeID']
          @order['order']['tradeID'] = options['order']['tradeID']
        end

        if options['order']['clientTradeID']
          @order['order']['clientTradeID'] = options['order']['clientTradeID']
        end

        if options['order']['clientExtensions']
          @order['order']['clientExtensions'] = options['order']['clientExtensions']
        end

        if options['order']['tradeClientExtensions']
          @order['order']['tradeClientExtensions'] = options['order']['tradeClientExtensions']
        end

        if ['LIMIT', 'STOP', 'MARKET_IF_TOUCHED'].include?(type)
          @order['order']['partialFill'] = 'DEFAULT_FILL'
        end

        if ['MARKET', 'LIMIT', 'STOP', 'MARKET_IF_TOUCHED'].include?(type)
          @order['order']['positionFill'] = options['order']['positionFill'] || 'DEFAULT'
        end

        if type == 'TRAILING_STOP_LOSS'
          @order['order']['distance'] = options['order']['distance']
        end

        unless type == 'MARKET'
          @order['order']['triggerCondition'] = options['order']['triggerCondition'] || 'DEFAULT'
        end
      end
    end

    def save
      $redis.sadd('backtest:active:orders', id) if order['order']['state'] == 'PENDING'
      $redis.srem('backtest:active:orders', id) if ['CANCELLED', 'TRIGGERED', 'FILLED'].include?(order['order']['state'])
      $redis.set("backtest:order:#{id}", order.to_json)
    end
  end
end
