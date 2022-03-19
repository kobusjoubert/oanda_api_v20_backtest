module OandaApiV20Backtest
  class Transaction
    attr_accessor :id, :batch_id, :order_id, :trade_id, :account_id, :type, :reason, :time, :options, :current_candle
    attr_reader   :transaction

    class << self
      def find(id)
        raise OandaApiV20Backtest::NotFound, "Transaction #{id} does not exist!" unless $redis.exists("backtest:transaction:#{id.to_i}")
        redis_transaction = JSON.parse($redis.get("backtest:transaction:#{id.to_i}"))
        Transaction.new(transaction: redis_transaction)
      end
    end

    def initialize(args = {})
      if args[:transaction]
        @transaction = args[:transaction]
        @id          = @transaction['transaction']['id']
        return
      end

      args.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      @options ||= {}

      @transaction = {
        'transaction' => {
          'type'      => type,
          'id'        => id.to_s,
          'batchID'   => batch_id.to_s,
          'userID'    => 1,
          'accountID' => account_id,
          'requestID' => '1',
          'time'      => time
        }
      }

      if reason
        @transaction['transaction']['reason'] = reason
      end

      if trade_id
        trade = Trade.find(trade_id)

        if trade.trade['trade']['clientExtensions'] && trade.trade['trade']['clientExtensions']['id']
          @transaction['transaction']['clientTradeID'] = trade.trade['trade']['clientExtensions']['id']
        end

        @transaction['transaction']['tradeID'] = trade_id.to_s

        if options['clientExtensions']
          @transaction['transaction']['tradeClientExtensionsModify'] = options['clientExtensions']
        end

        if options['takeProfit']
          @transaction['transaction'].merge!(
            'triggerCondition' => options['takeProfit']['triggerCondition'] || 'DEFAULT', # 'TRIGGER_DEFAULT'?
            'timeInForce'      => options['takeProfit']['timeInForce'] || 'GTC',
            'price'            => options['takeProfit']['price'].to_s
          )
        end

        if options['stopLoss']
          @transaction['transaction'].merge!(
            'triggerCondition' => options['stopLoss']['triggerCondition'] || 'DEFAULT', # 'TRIGGER_DEFAULT'?
            'timeInForce'      => options['stopLoss']['timeInForce'] || 'GTC',
            'price'            => options['stopLoss']['price'].to_s
          )
        end

        if options['trailingStopLoss']
          @transaction['transaction'].merge!(
            'triggerCondition' => options['trailingStopLoss']['triggerCondition'] || 'DEFAULT', # 'TRIGGER_DEFAULT'?
            'timeInForce'      => options['trailingStopLoss']['timeInForce'] || 'GTC',
            'price'            => options['trailingStopLoss']['price'].to_s
          )
        end
      end

      if order_id
        @transaction['transaction']['orderID'] = order_id.to_s

        if options['clientExtensions']
          @transaction['transaction']['clientExtensionsModify'] = options['clientExtensions']
        end

        if options['tradeClientExtensions']
          @transaction['transaction']['tradeClientExtensionsModify'] = options['tradeClientExtensions']
        end
      end

      if options['order']
        order_type   = options['order']['type']
        trade_opened = trade_opened_hash(nil, nil, price: options['order']['price'], units: options['order']['units'], id: id)

        @transaction['transaction']['timeInForce'] = options['order']['timeInForce'] || 'GTC'

        if order_type == 'MARKET'
          @transaction['transaction'].merge!(
            # 'orderID'         => order_id,
            'price'           => price_on_enter(current_candle, options).to_s,
            'pl'              => '0.0000',
            'financing'       => '0.0000',
            'commission'      => '0.0000',
            'accountBalance'  => '1.0000',
            'tradeOpened'     => trade_opened,
            'fullPrice'      => {
              'closeoutBid' => '1.00000',
              'closeoutAsk' => '1.00000',
              'timestamp'   => time,
              'bids' => [
                {
                  'price'     => current_candle['bid']['c'],
                  'liquidity' => '10000000'
                }
              ],
              'asks' => [
                {
                  'price'     => current_candle['ask']['c'],
                  'liquidity' => '10000000'
                }
              ]
            }
          )
        end

        if options['order']['clientExtensions']
          @transaction['transaction']['clientExtensions'] = options['order']['clientExtensions']
        end

        if options['order']['tradeClientExtensions']
          @transaction['transaction']['tradeClientExtensions'] = options['order']['tradeClientExtensions']
        end

        if options['order']['instrument']
          @transaction['transaction']['instrument'] = options['order']['instrument']
        end

        if options['order']['units']
          @transaction['transaction']['units'] = options['order']['units']
        end

        if options['order']['price']
          @transaction['transaction']['price'] = options['order']['price']
        end

        if options['order']['priceBound']
          @transaction['transaction']['priceBound'] = options['order']['priceBound']
        end

        if options['order']['takeProfitOnFill']
          @transaction['transaction']['takeProfitOnFill'] = options['order']['takeProfitOnFill']
        end

        if options['order']['stopLossOnFill']
          @transaction['transaction']['stopLossOnFill'] = options['order']['stopLossOnFill']
        end

        if options['order']['trailingStopLossOnFill']
          @transaction['transaction']['trailingStopLossOnFill'] = options['order']['trailingStopLossOnFill']
        end

        if options['order']['gtdTime']
          @transaction['transaction']['gtdTime'] = options['order']['gtdTime']
        end

        if options['order']['tradeID']
          @transaction['transaction']['tradeID'] = options['order']['tradeID']
        end

        if options['order']['clientTradeID']
          @transaction['transaction']['clientTradeID'] = options['order']['clientTradeID']
        end

        if ['LIMIT', 'STOP', 'MARKET_IF_TOUCHED'].include?(order_type)
          @transaction['transaction']['partialFill'] = 'DEFAULT'
        end

        if ['MARKET', 'LIMIT', 'STOP', 'MARKET_IF_TOUCHED'].include?(order_type)
          @transaction['transaction']['positionFill'] = options['order']['positionFill'] || 'DEFAULT'
        end

        if order_type == 'TRAILING_STOP_LOSS'
          @transaction['transaction']['distance'] = options['order']['distance']
        end

        unless order_type == 'MARKET'
          @transaction['transaction']['triggerCondition'] = options['order']['triggerCondition'] || 'DEFAULT'
        end
      end
    end

    def save
      $redis.sadd('backtest:transactions', id)
      $redis.set("backtest:transaction:#{id}", transaction.to_json)
    end

    private

    def price_on_enter(current_candle, options)
      return options['order']['price'].to_f if options['order']['price']

      trigger_price = TRIGGER_CONDITION[options['order']['triggerCondition']]
      trigger_price = TRIGGER_CONDITION['DEFAULT'] unless trigger_price
      type          = options['order']['units'].to_f > 0 ? :long : :short

      current_candle[trigger_price[type]]['c'].to_f
    end

    def half_spread_cost_on_enter(trade, order = nil, options = {})
      half_spread_cost_on(:enter, trade, order, options)
    end

    # If you don't supply order, you have to supply options[:units].
    # If you don't supply order and trade, you have to supply options[:units].
    def half_spread_cost_on(enter_or_exit, trade = nil, order = nil, options = {})
      units = options[:units].to_i if options[:units]
      raise OandaApiV20Backtest::Error, 'You must supply the order parameter when calculating half_spread_cost_on enter when not supplying the units!' if enter_or_exit == :enter && order.nil? && trade.nil? && options[:units].nil?
      raise OandaApiV20Backtest::Error, 'You must supply the order parameter when calculating half_spread_cost_on exit when not supplying the units!' if enter_or_exit == :exit && order.nil? && options[:units].nil?

      trigger_price = {
        enter: { long: 'ask', short: 'bid' },
        exit:  { long: 'bid', short: 'ask' }
      }

      type =
        if trade
          trade.trade['trade']['initialUnits'].to_i > 0 ? :long : :short
        else
          if order
            order.order['order']['units'].to_i > 0 ? :long : :short
          else
            units.to_i > 0 ? :long : :short
          end
        end

      spread_price      = trigger_price[enter_or_exit][type]
      spread_difference = (current_candle[spread_price]['c'].to_f - current_candle['mid']['c'].to_f).abs

      unless units
        units =
          case enter_or_exit
          when :enter
            trade.trade['trade']['initialUnits'].to_i
          when :exit
            if ['STOP_LOSS', 'TRAILING_STOP_LOSS'].include?(order.order['order']['type'])
              trade.trade['trade']['initialUnits'].to_i
            else
              order.order['order']['units'].to_i
            end
          end
      end

      (spread_difference * units).abs.round(5)
    end

    # Hashes.

    # If you don't supply order, you have to supply options[:price] & options[:units].
    # If you don't supply order and trade, you have to supply options[:price], options[:units] & options[:id].
    def trade_opened_hash(trade = nil, order = nil, options = {})
      trade_id         = options[:id] || trade.id
      price            = options[:price] || order.order['order']['price']
      units            = options[:units] || trade.trade['trade']['currentUnits'].to_i
      half_spread_cost = options[:half_spread_cost] || half_spread_cost_on_enter(trade, order, options)

      {
        'tradeID'                => trade_id.to_s,
        'units'                  => units.to_s,
        'price'                  => price.to_s,
        'halfSpreadCost'         => half_spread_cost.to_s,
        'guaranteedExecutionFee' => '0.0000',
        'initialMarginRequired'  => '0.0000'
      }
    end
  end
end
