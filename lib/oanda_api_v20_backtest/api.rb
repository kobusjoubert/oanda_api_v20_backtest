module OandaApiV20Backtest
  class Api
    include Accounts
    include Instruments
    include Orders
    include Trades
    include Positions
    # include Transactions
    # include Pricing

    attr_accessor :client, :account_id, :last_action, :last_arguments, :last_transaction_id, :backtest_index, :backtest_time
    attr_reader   :all_candles, :current_candle, :current_candles, :time
    attr_writer   :instrument

    def initialize(options = {})
      options.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      raise OandaApiV20::ApiError, 'No client object was supplid.' unless client

      # OandaWorker should pass backtest_index and backtest_time along.
      # OandaTrader does not need to pass this along as no processing on candles are done there.
      return unless backtest_index && backtest_time

      @last_transaction_id ||= $redis.get('backtest:last_transaction_id').to_i
      # @current_candle      = $candle_server.get_candle(backtest_index) # TODO: Deprecate!
      @current_candles     = $candle_server.get_candles(backtest_index, 2)['candles'] # Used in crossed_over?
      @current_candle      = current_candles.last
      @time                = backtest_time.iso8601
      account              = Account.new

      # 1) Loop over all active orders and check if:
      #
      #   MARKET_IF_TOUCHED, LIMIT and STOP orders should be filled as trades with TP, SL and TS orders on fill.
      #   Only fill these orders if sufficient units available, if not, close the order.
      #
      #   TAKE_PROFIT, STOP_LOSS or TRAILING_STOP_LOSS orders should be filled and the related trade closed.
      #
      #   Candle Conflict!
      #
      #   If there are both TAKE_PROFIT, STOP_LOSS or TRAILING_STOP_LOSS as well as MARKET_IF_TOUCHED, LIMIT and STOP
      #   orders in the backtest:active:orders list, and a STOP_LOSS and LIMIT order both got triggered with the
      #   current_candle, the STOP_LOSS should take precedence over the LIMIT order. There is no way for us to know
      #   which got triggered first, so we take worst case scenario and carry on to the next candle.

      # 2) Loop over open positions and check if margin closeout was triggered.

      # !) This should only check active orders once for each bactest_time or candle.
      return if $redis.get('backtest:last_backtest_time') == backtest_time.to_s
      $redis.set('backtest:last_backtest_time', backtest_time)

      active_orders              = $redis.smembers('backtest:active:orders')
      new_trade_needed           = false
      stop_trade_out_immediately = false

      stop_loss_or_take_profit_order_triggered_before_market_order = false

      # 1) Loop over all active orders.
      active_orders.each do |id|
        i                       = 0
        related_transaction_ids = []
        batch_id                = (last_transaction_id + i + 1).to_s
        order                   = Order.find(id)

        catch :trigger_stop_loss_and_take_profit_orders_before_market_orders do
          if ['MARKET_IF_TOUCHED', 'LIMIT', 'STOP'].include?(order.order['order']['type'])
            next unless order_triggered?(order)

            # STOP_LOSS orders take presedence when triggered with the current_candle.
            active_orders.each do |id|
              lookup_order = Order.find(id)

              if ['TAKE_PROFIT', 'STOP_LOSS', 'TRAILING_STOP_LOSS'].include?(lookup_order.order['order']['type'])
                trade = Trade.find(lookup_order.order['order']['tradeID'])
                trade.current_candle = current_candle
                throw :trigger_stop_loss_and_take_profit_orders_before_market_orders if order_triggered?(lookup_order, trade)
              end
            end

            i += 1

            order_units = order.order['order']['units'].to_i

            # Close order if insuficcient margin available.
            #
            # NOTE: Oanda does not close current trades first before opening new orders.
            if units_available(order, account) < order_units.abs
              cancel_order_transaction = Transaction.new(
                id:         (last_transaction_id + i).to_s,
                order_id:   order.order['order']['id'],
                batch_id:   batch_id,
                account_id: account_id,
                type:       'ORDER_CANCEL',
                reason:     'INSUFFICIENT_MARGIN',
                time:       time
              )

              order.order['order'].merge!(
                'state'                   => 'CANCELLED',
                'cancellingTransactionID' => cancel_order_transaction.id,
                'cancelledTime'           => time
              )

              cancel_order_transaction.save
              order.save
              next
            end

            # Sufficient margin available to open trades. Let's carry on!
            order_fill_transaction = Transaction.new(
              id:             (last_transaction_id + i).to_s,
              batch_id:       batch_id,
              order_id:       order.id,
              account_id:     account_id,
              type:           'ORDER_FILL',
              reason:         "#{order.order['order']['type']}_ORDER",
              time:           time,
              current_candle: current_candle
            )

            # TODO: Only the DEFAULT (REDUCE_FIRST) behavior is supported for now. Implement the REDUCE_ONLY & OPEN_ONLY when needed.
            if ['DEFAULT', 'REDUCE_FIRST'].include?(order.order['order']['positionFill'])
              position               = Position.find_by_instrument(order.order['order']['instrument'])
              long_units             = position.position['position']['long']['units'].to_i
              short_units            = position.position['position']['short']['units'].to_i
              trade_ids              = []
              trade_opened           = nil
              trade_reduced          = nil
              trades_closed          = []
              total_pl               = 0.0
              total_half_spread_cost = 0.0
              new_trade_needed       = false # Need this here, sometimes 1 order triggers a trade and the next order closes it.

              # Add long or short trade.
              if long_units == 0 && short_units == 0 || long_units > 0 && order_units > 0 || short_units < 0 && order_units < 0
                units            = order_units
                new_trade_needed = true
              end

              # Reduce long trades.
              if long_units > 0 && order_units < 0
                trade_ids        = position.position['position']['long']['tradeIDs'] 
                units            = long_units + order_units
                new_trade_needed = true if units < 0
              end

              # Reduce short trades.
              if short_units < 0 && order_units > 0
                trade_ids        = position.position['position']['short']['tradeIDs']
                units            = short_units + order_units
                new_trade_needed = true if units > 0
              end

              if long_units > 0 && order_units < 0 || short_units < 0 && order_units > 0
                units_to_reduce = order_units.abs
              end

              # Close or reduce trades until units_to_reduce has been met.
              trade_ids.each do |id|
                trade_to_close_or_reduce                = Trade.find(id)
                trade_to_close_or_reduce.current_candle = current_candle
                units_to_reduce                         -= trade_to_close_or_reduce.trade['trade']['currentUnits'].to_i.abs

                # Close trades.
                if units_to_reduce >= 0
                  trade_closed            = trade_closed_hash(trade_to_close_or_reduce, order)
                  trades_closed           << trade_closed
                  total_pl                += trade_closed['realizedPL'].to_f
                  total_half_spread_cost  += trade_closed['halfSpreadCost'].to_f
                  closing_transaction_ids = (trade_to_close_or_reduce.trade['trade']['closingTransactionIDs'] || []) + [order_fill_transaction.id]

                  trade_to_close_or_reduce.trade['trade'].merge!(
                    'state'                 => 'CLOSED',
                    'currentUnits'          => '0',
                    'realizedPL'            => trade_realized_pl(trade_to_close_or_reduce, closing_transaction_ids.map{ |id| id unless id == order_fill_transaction.id }.compact, trade_closed['realizedPL']).to_s,
                    'averageClosePrice'     => average_close_price(order: order).to_s,
                    'closingTransactionIDs' => closing_transaction_ids,
                    'closeTime'             => time
                  )

                  # Cancel TP, SL and TS orders.
                  if trade_to_close_or_reduce.trade['trade']['takeProfitOrder']
                    i += 1

                    cancel_take_profit_transaction = Transaction.new(
                      id:         (last_transaction_id + i).to_s,
                      order_id:   trade_to_close_or_reduce.trade['trade']['takeProfitOrder']['id'],
                      batch_id:   batch_id,
                      account_id: account_id,
                      type:       'ORDER_CANCEL',
                      reason:     'LINKED_TRADE_CLOSED',
                      time:       time
                    )

                    cancel_take_profit_transaction.transaction['transaction'].merge!(
                      'closedTradeID'           => trade_to_close_or_reduce.id,
                      'tradeCloseTransactionID' => order_fill_transaction.id
                    )

                    cancelled_take_profit_order = Order.find(cancel_take_profit_transaction.order_id)

                    cancelled_take_profit_order.order['order'].merge!(
                      'state'                   => 'CANCELLED',
                      'cancellingTransactionID' => cancel_take_profit_transaction.id,
                      'cancelledTime'           => time
                    )

                    trade_to_close_or_reduce.trade['trade']['takeProfitOrder'] = cancelled_take_profit_order.order['order']
                  end

                  if trade_to_close_or_reduce.trade['trade']['stopLossOrder']
                    i += 1

                    cancel_stop_loss_transaction = Transaction.new(
                      id:         (last_transaction_id + i).to_s,
                      order_id:   trade_to_close_or_reduce.trade['trade']['stopLossOrder']['id'],
                      batch_id:   batch_id,
                      account_id: account_id,
                      type:       'ORDER_CANCEL',
                      reason:     'LINKED_TRADE_CLOSED',
                      time:       time
                    )

                    cancel_stop_loss_transaction.transaction['transaction'].merge!(
                      'closedTradeID'           => trade_to_close_or_reduce.id,
                      'tradeCloseTransactionID' => order_fill_transaction.id
                    )

                    cancelled_stop_loss_order = Order.find(cancel_stop_loss_transaction.order_id)

                    cancelled_stop_loss_order.order['order'].merge!(
                      'state'                   => 'CANCELLED',
                      'cancellingTransactionID' => cancel_stop_loss_transaction.id,
                      'cancelledTime'           => time
                    )

                    trade_to_close_or_reduce.trade['trade']['stopLossOrder'] = cancelled_stop_loss_order.order['order']
                  end

                  if trade_to_close_or_reduce.trade['trade']['trailingStopLossOrder']
                    i += 1

                    cancel_trailing_stop_loss_transaction = Transaction.new(
                      id:         (last_transaction_id + i).to_s,
                      order_id:   trade_to_close_or_reduce.trade['trade']['trailingStopLossOrder']['id'],
                      batch_id:   batch_id,
                      account_id: account_id,
                      type:       'ORDER_CANCEL',
                      reason:     'LINKED_TRADE_CLOSED',
                      time:       time
                    )

                    cancel_trailing_stop_loss_transaction.transaction['transaction'].merge!(
                      'closedTradeID'           => trade_to_close_or_reduce.id,
                      'tradeCloseTransactionID' => order_fill_transaction.id
                    )

                    cancelled_trailing_stop_loss_order = Order.find(cancel_trailing_stop_loss_transaction.order_id)

                    cancelled_trailing_stop_loss_order.order['order'].merge!(
                      'state'                   => 'CANCELLED',
                      'cancellingTransactionID' => cancel_trailing_stop_loss_transaction.id,
                      'cancelledTime'           => time
                    )

                    trade_to_close_or_reduce.trade['trade']['trailingStopLossOrder'] = cancelled_trailing_stop_loss_order.order['order']
                  end

                  if cancel_take_profit_transaction
                    related_transaction_ids << cancel_take_profit_transaction.id
                    cancel_take_profit_transaction.save
                    cancelled_take_profit_order.save
                  end

                  if cancel_stop_loss_transaction
                    related_transaction_ids << cancel_stop_loss_transaction.id
                    cancel_stop_loss_transaction.save
                    cancelled_stop_loss_order.save
                  end

                  if cancel_trailing_stop_loss_transaction
                    related_transaction_ids << cancel_trailing_stop_loss_transaction.id
                    cancel_trailing_stop_loss_transaction.save
                    cancelled_trailing_stop_loss_order.save
                  end

                  trade_to_close_or_reduce.save
                end

                # Reduce trades.
                if units_to_reduce < 0
                  units_remaining         = trade_to_close_or_reduce.trade['trade']['currentUnits'].to_i.abs + units_to_reduce
                  type                    = trade_to_close_or_reduce.trade['trade']['currentUnits'].to_i > 0 ? :long : :short
                  units_remaining         = -units_remaining if type == :short
                  trade_reduced           = trade_reduced_hash(trade_to_close_or_reduce, order, units: -units_to_reduce)
                  total_pl                += trade_reduced['realizedPL'].to_f
                  total_half_spread_cost  += trade_reduced['halfSpreadCost'].to_f
                  closing_transaction_ids = (trade_to_close_or_reduce.trade['trade']['closingTransactionIDs'] || []) + [order_fill_transaction.id]

                  trade_to_close_or_reduce.trade['trade'].merge!(
                    'currentUnits'          => units_remaining.to_s,
                    'realizedPL'            => trade_realized_pl(trade_to_close_or_reduce, closing_transaction_ids.map{ |id| id unless id == order_fill_transaction.id }.compact, trade_reduced['realizedPL']).to_s,
                    'averageClosePrice'     => average_close_price(order: order).to_s,
                    'closingTransactionIDs' => closing_transaction_ids
                  )

                  trade_to_close_or_reduce.save
                end

                break if units_to_reduce <= 0
              end

              # Open trade if sufficient margin available.
              if new_trade_needed # && units_available(order, account) >= units # NOTE: Uncommented for now to prevent any surprises.
                trade_options = {
                  'order' => {
                    'instrument'       => order.order['order']['instrument'],
                    'price'            => order.order['order']['price'].to_s,
                    'units'            => units.to_s,
                    'state'            => 'OPEN',
                    'triggerCondition' => order.order['order']['triggerCondition'] || 'DEFAULT'
                  }
                }

                trade = Trade.new(
                  id:             order_fill_transaction.id,
                  time:           time,
                  options:        trade_options,
                  current_candle: current_candle
                )

                trade_opened = trade_opened_hash(trade, order)

                order.order['order']['tradeOpenedID'] = trade.id

                if order.order['order']['takeProfitOnFill']
                  i += 1

                  take_profit_order = Order.new(
                    id:       (last_transaction_id + i).to_s,
                    trade_id: trade.id,
                    time:     time,
                    type:     'TAKE_PROFIT',
                    options:  { 'takeProfit' => order.order['order']['takeProfitOnFill'] }
                  )

                  trade.trade['trade']['takeProfitOrder'] = take_profit_order.order['order']
                end

                if order.order['order']['stopLossOnFill']
                  i += 1

                  stop_loss_order = Order.new(
                    id:       (last_transaction_id + i).to_s,
                    trade_id: trade.id,
                    time:     time,
                    type:     'STOP_LOSS',
                    options:  { 'stopLoss' => order.order['order']['stopLossOnFill'] }
                  )

                  trade.trade['trade']['stopLossOrder'] = stop_loss_order.order['order']
                end

                if order.order['order']['trailingStopLossOnFill']
                  i += 1

                  trailing_stop_loss_order = Order.new(
                    id:       (last_transaction_id + i).to_s,
                    trade_id: trade.id,
                    time:     time,
                    type:     'TRAILING_STOP_LOSS',
                    options:  { 'trailingStopLoss' => order.order['order']['trailingStopLossOnFill'] }
                  )

                  trade.trade['trade']['trailingStopLossOrder'] = trailing_stop_loss_order.order['order']
                end
              end
            end

            order_fill_transaction.transaction['transaction'].merge!(
              'instrument'                    => order.order['order']['instrument'],
              'units'                         => order.order['order']['units'],
              'price'                         => price_on_enter(order).to_s,
              'pl'                            => total_pl.to_s,
              'fullVWAP'                      => price_on_enter(order).to_s,
              'financing'                     => '0.0000',
              'commission'                    => '0.0000',
              'accountBalance'                => account.balance.to_s,
              'halfSpreadCost'                => total_half_spread_cost.to_s,
              'gainQuoteHomeConversionFactor' => '1',
              'lossQuoteHomeConversionFactor' => '1',
              'guaranteedExecutionFee'        => '0.0000',
              'fullPrice' => {
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

            order_fill_transaction.transaction['transaction']['tradeOpened']  = trade_opened if trade_opened
            order_fill_transaction.transaction['transaction']['tradeReduced'] = trade_reduced if trade_reduced
            order_fill_transaction.transaction['transaction']['tradesClosed'] = trades_closed if trades_closed.any?

            order.order['order'].merge!(
              'fillingTransactionID' => order_fill_transaction.id,
              'state'                => 'FILLED',
              'filledTime'           => time
            )

            order.order['order']['tradeOpenedID']  = trade_opened['tradeID'] if trade_opened
            order.order['order']['tradeReducedID'] = trade_reduced['tradeID'] if trade_reduced
            order.order['order']['tradeClosedIDs'] = trades_closed.map{ |t| t['tradeID'] } if trades_closed.any?

            take_profit_order.save if take_profit_order
            stop_loss_order.save if stop_loss_order
            trailing_stop_loss_order.save if trailing_stop_loss_order
            order_fill_transaction.save
            order.save
            trade.save if trade

            # If the trade was just opened and the stop loss triggered with the same candle, reset the order object and stop the trade out.
            if (new_trade_needed || trade_opened) && order_triggered?(stop_loss_order, trade)
              order                      = stop_loss_order
              stop_trade_out_immediately = true
            end
          end
        end

        if ['TAKE_PROFIT', 'STOP_LOSS', 'TRAILING_STOP_LOSS'].include?(order.order['order']['type'])
          trade                = Trade.find(order.order['order']['tradeID'])
          trade.current_candle = current_candle
          next unless order_triggered?(order, trade)
          units                = (-trade.trade['trade']['currentUnits'].to_i)
          trades_closed        = []

          raise OandaApiV20Backtest::Error, "Possible conflict! An old trade closed while an order was triggered as a new trade. Use smaller time frame candles to backtest with or increase pip levels in the strategy." if new_trade_needed && !stop_trade_out_immediately

          active_orders.each do |id|
            lookup_order = Order.find(id)

            if ['MARKET_IF_TOUCHED', 'LIMIT', 'STOP'].include?(lookup_order.order['order']['type'])
              stop_loss_or_take_profit_order_triggered_before_market_order = true if order_triggered?(lookup_order)
            end
          end

          i += 1

          order_fill_transaction = Transaction.new(
            id:             (last_transaction_id + i).to_s,
            batch_id:       batch_id,
            order_id:       order.id,
            account_id:     account_id,
            type:           'ORDER_FILL',
            reason:         "#{order.order['order']['type']}_ORDER",
            time:           time,
            current_candle: current_candle
          )

          realized_pl   = transaction_realized_pl(trade, order)
          trade_closed  = trade_closed_hash(trade, order, units: units, realized_pl: realized_pl)
          trades_closed << trade_closed

          order_fill_transaction.transaction['transaction'].merge!(
            'instrument'                    => trade.trade['trade']['instrument'],
            'units'                         => units.to_s,
            'price'                         => price_on_exit(trade, order).to_s,
            'pl'                            => realized_pl.to_s,
            'fullVWAP'                      => price_on_exit(trade, order).to_s,
            'financing'                     => '0.0000',
            'commission'                    => '0.0000',
            'accountBalance'                => '1.0000',
            'halfSpreadCost'                => trade_closed['halfSpreadCost'].to_s,
            'gainQuoteHomeConversionFactor' => '1',
            'lossQuoteHomeConversionFactor' => '1',
            'guaranteedExecutionFee'        => '0.0000',
            'tradesClosed'   => trades_closed,
            'fullPrice' => {
              'closeoutBid' => '1.00000',
              'closeoutAsk' => '1.00000',
              'timestamp' => time,
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

          # if trade.trade['trade']['clientExtensions'] && trade.trade['trade']['clientExtensions']['id']
          #   order_fill_transaction.transaction['transaction']['tradesClosed'].first['clientTradeID'] = trade.trade['trade']['clientExtensions']['id']
          # end

          order.order['order'].merge!(
            'tradeClosedIDs'       => [trade.id],
            'fillingTransactionID' => order_fill_transaction.id,
            'state'                => 'FILLED',
            'filledTime'           => time
          )

          closing_transaction_ids = (trade.trade['trade']['closingTransactionIDs'] || []) + [order_fill_transaction.id]

          trade.trade['trade'].merge!(
            'state'                 => 'CLOSED',
            'currentUnits'          => '0',
            'realizedPL'            => trade_realized_pl(trade, closing_transaction_ids.map{ |id| id unless id == order_fill_transaction.id }.compact, trade_closed['realizedPL']).to_s,
            'averageClosePrice'     => average_close_price(order: order).to_s,
            'closingTransactionIDs' => closing_transaction_ids,
            'closeTime'             => time,
          )

          trade.trade['trade']['takeProfitOrder'] = order.order['order'] if order.order['order']['type'] == 'TAKE_PROFIT'
          trade.trade['trade']['stopLossOrder'] = order.order['order'] if order.order['order']['type'] == 'STOP_LOSS'
          trade.trade['trade']['trailingStopLossOrder'] = order.order['order'] if order.order['order']['type'] == 'TRAILING_STOP_LOSS'

          if trade.trade['trade']['takeProfitOrder'] && ['STOP_LOSS', 'TRAILING_STOP_LOSS'].include?(order.order['order']['type'])
            i += 1

            cancel_take_profit_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['takeProfitOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'LINKED_TRADE_CLOSED',
              time:       time
            )

            cancel_take_profit_transaction.transaction['transaction'].merge!(
              'closedTradeID'           => trade.id,
              'tradeCloseTransactionID' => order_fill_transaction.id
            )

            cancelled_take_profit_order = Order.find(cancel_take_profit_transaction.order_id)

            cancelled_take_profit_order.order['order'].merge!(
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_take_profit_transaction.id,
              'cancelledTime'           => time
            )

            trade.trade['trade']['takeProfitOrder'] = cancelled_take_profit_order.order['order']

            cancel_take_profit_transaction.save
            cancelled_take_profit_order.save
          end

          if trade.trade['trade']['stopLossOrder'] && ['TAKE_PROFIT', 'TRAILING_STOP_LOSS'].include?(order.order['order']['type'])
            i += 1

            cancel_stop_loss_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['stopLossOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'LINKED_TRADE_CLOSED',
              time:       time
            )

            cancel_stop_loss_transaction.transaction['transaction'].merge!(
              'closedTradeID'           => trade.id,
              'tradeCloseTransactionID' => order_fill_transaction.id
            )

            cancelled_stop_loss_order = Order.find(cancel_stop_loss_transaction.order_id)

            cancelled_stop_loss_order.order['order'].merge!(
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_stop_loss_transaction.id,
              'cancelledTime'           => time
            )

            trade.trade['trade']['stopLossOrder'] = cancelled_stop_loss_order.order['order']

            cancel_stop_loss_transaction.save
            cancelled_stop_loss_order.save
          end

          if trade.trade['trade']['trailingStopLossOrder'] && ['TAKE_PROFIT', 'STOP_LOSS'].include?(order.order['order']['type'])
            i += 1

            cancel_trailing_stop_loss_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['trailingStopLossOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'LINKED_TRADE_CLOSED',
              time:       time
            )

            cancel_trailing_stop_loss_transaction.transaction['transaction'].merge!(
              'closedTradeID'           => trade.id,
              'tradeCloseTransactionID' => order_fill_transaction.id
            )

            cancelled_trailing_stop_loss_order = Order.find(cancel_trailing_stop_loss_transaction.order_id)

            cancelled_trailing_stop_loss_order.order['order'].merge!(
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_trailing_stop_loss_transaction.id,
              'cancelledTime'           => time
            )

            trade.trade['trade']['trailingStopLossOrder'] = cancelled_trailing_stop_loss_order.order['order']

            cancel_trailing_stop_loss_transaction.save
            cancelled_trailing_stop_loss_order.save
          end

          order_fill_transaction.save
          order.save
          trade.save
        end

        @last_transaction_id = last_transaction_id + i
        $redis.set('backtest:last_transaction_id', last_transaction_id)
      
        # If a STOP_LOSS and target LIMIT order both got triggered with the current_candle, the STOP_LOSS took precedence and the target LIMIT order was not filled. Carry on to the next candle.
        break if stop_loss_or_take_profit_order_triggered_before_market_order
      end

      # 2) Find current instrument being backtested from first trade and see if a margin closeout has been triggered.
      $redis.smembers('backtest:active:trades').each do |id|
        i                    = 0
        batch_id             = (last_transaction_id + i + 1).to_s
        trade                = Trade.find(id)
        trade.current_candle = current_candle
        instrument           = trade.trade['trade']['instrument']
        position             = Position.find_by_instrument(instrument)

        raise OandaApiV20Backtest::Error, "Position long units cannot be negative" if position.position['position']['long']['units'].to_i < 0
        raise OandaApiV20Backtest::Error, "Position short units cannot be positive" if position.position['position']['short']['units'].to_i > 0

        break unless margin_clouseout?(position, account)

        i += 1

        related_transaction_ids = []
        trades_closed           = []
        total_pl                = 0.0
        type                    = :long if position.position['position']['long']['units'].to_i > 0
        type                    = :short if position.position['position']['short']['units'].to_i < 0

        market_order_transaction = Transaction.new(
          id:             (last_transaction_id + i).to_s,
          batch_id:       batch_id,
          account_id:     account_id,
          type:           'MARKET_ORDER',
          reason:         'MARGIN_CLOSEOUT',
          time:           time
        )

        market_order_transaction.transaction['transaction']['marginCloseout'] = { 'reason' => 'MARGIN_CHECK_VIOLATION' }

        case type
        when :long
          units     = (-position.position['position']['long']['units'].to_i).to_s
          trade_ids = position.position['position']['long']['tradeIDs']
          price     = price_on_exit(:long)
        when :short
          units     = (-position.position['position']['short']['units'].to_i).to_s
          trade_ids = position.position['position']['short']['tradeIDs']
          price     = price_on_exit(:short)
        end

        # Not sure if this needs to be added.
        market_order_transaction.transaction['transaction'].merge!(
          'instrument' => instrument,
          'units'      => units
        )

        market_order_transaction.save

        $redis.sadd('backtest:margin_closeout_trades', trade_ids)

        margin_price = margin_closeout_price(position, account)

        # Copied from Positions client.account('account_id').position('EUR_CAD', options).close
        trade_ids.each do |id|
          trade                   = Trade.find(id)
          trade.current_candle    = current_candle
          closing_transaction_ids = (trade.trade['trade']['closingTransactionIDs'] || []) + [market_order_transaction.id]
          units                   = (-trade.trade['trade']['currentUnits'].to_i)
          price                   = price_on_exit(trade)
          realized_pl             = transaction_realized_pl(trade, nil, units: units, price: price)
          trade_closed            = trade_closed_hash(trade, nil, price: margin_price, units: units, realized_pl: realized_pl)
          trades_closed           << trade_closed
          total_pl                += trade_closed['realizedPL'].to_f

          trade.trade['trade'].merge!(
            'state'                 => 'CLOSED',
            'currentUnits'          => '0',
            'realizedPL'            => trade_closed['realizedPL'],
            'averageClosePrice'     => average_close_price(price: margin_price),
            'closingTransactionIDs' => closing_transaction_ids,
            'closeTime'             => time
          )

          if trade.trade['trade']['takeProfitOrder']
            i += 1

            cancel_take_profit_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['takeProfitOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'LINKED_TRADE_CLOSED',
              time:       time,
              options:    options
            )

            cancel_take_profit_transaction.transaction['transaction'].merge!(
              'closedTradeID'           => trade.id,
              'tradeCloseTransactionID' => market_order_transaction.id
            )

            cancelled_take_profit_order = Order.find(cancel_take_profit_transaction.order_id)

            cancelled_take_profit_order.order['order'].merge!(
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_take_profit_transaction.id,
              'cancelledTime'           => time
            )

            trade.trade['trade']['takeProfitOrder'] = cancelled_take_profit_order.order['order']
          end

          if trade.trade['trade']['stopLossOrder']
            i += 1

            cancel_stop_loss_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['stopLossOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'LINKED_TRADE_CLOSED',
              time:       time,
              options:    options
            )

            cancel_stop_loss_transaction.transaction['transaction'].merge!(
              'closedTradeID'           => trade.id,
              'tradeCloseTransactionID' => market_order_transaction.id
            )

            cancelled_stop_loss_order = Order.find(cancel_stop_loss_transaction.order_id)

            cancelled_stop_loss_order.order['order'].merge!(
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_stop_loss_transaction.id,
              'cancelledTime'           => time
            )

            trade.trade['trade']['stopLossOrder'] = cancelled_stop_loss_order.order['order']
          end

          if trade.trade['trade']['trailingStopLossOrder']
            i += 1

            cancel_trailing_stop_loss_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['trailingStopLossOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'LINKED_TRADE_CLOSED',
              time:       time,
              options:    options
            )

            cancel_trailing_stop_loss_transaction.transaction['transaction'].merge!(
              'closedTradeID'           => trade.id,
              'tradeCloseTransactionID' => market_order_transaction.id
            )

            cancelled_trailing_stop_loss_order = Order.find(cancel_trailing_stop_loss_transaction.order_id)

            cancelled_trailing_stop_loss_order.order['order'].merge!(
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_trailing_stop_loss_transaction.id,
              'cancelledTime'           => time
            )

            trade.trade['trade']['trailingStopLossOrder'] = cancelled_trailing_stop_loss_order.order['order']
          end

          if cancel_take_profit_transaction
            related_transaction_ids << cancel_take_profit_transaction.id
            cancel_take_profit_transaction.save
          end

          if cancel_stop_loss_transaction
            related_transaction_ids << cancel_stop_loss_transaction.id
            cancel_stop_loss_transaction.save
          end

          if cancel_trailing_stop_loss_transaction
            related_transaction_ids << cancel_trailing_stop_loss_transaction.id
            cancel_trailing_stop_loss_transaction.save
          end

          cancelled_take_profit_order.save if cancelled_take_profit_order
          cancelled_stop_loss_order.save if cancelled_stop_loss_order
          cancelled_trailing_stop_loss_order.save if cancelled_trailing_stop_loss_order
          trade.save
        end

        # Only need to loop over the first trade to figure out if a margin closeout has triggered.
        break
      end
    end

    class << self
      def api_methods
        Accounts.instance_methods + Instruments.instance_methods + Orders.instance_methods + Trades.instance_methods + Positions.instance_methods # + Transactions.instance_methods + Pricing.instance_methods
      end
    end

    self.api_methods.each do |method_name|
      original_method = instance_method(method_name)

      define_method(method_name) do |*args, &block|
        # Add the block below before each of the api_methods to set the last_action and last_arguments.
        # Return the OandaApiV20::Api object to allow for method chaining when any of the api_methods have been called.
        # Only make an HTTP request to Oanda API When an action method like show, update, cancel, close or create was called.
        set_last_action_and_arguments(method_name, *args)
        return self unless http_verb

        original_method.bind(self).call(*args, &block)
      end
    end

    def method_missing(name, *args, &block)
      case name
      when :show, :create, :update, :cancel, :close
        set_http_verb(name, last_action)

        if respond_to?(last_action)
          api_result = last_arguments.nil? || last_arguments.empty? ? send(last_action, &block) : send(last_action, *last_arguments, &block)
          set_last_transaction_id(api_result['lastTransactionID']) if api_result['lastTransactionID']
        end

        self.http_verb = nil
        api_result
      else
        super
      end
    end

    protected

    def all_candles(count)
      @all_candles ||= $candle_server.get_candles(backtest_index, count)
    end

    # When there is an active trade, use the current candle's high and low price movement and the trade's triggered price to determine if the order got filled.
    def order_triggered?(order, trade = nil)
      trigger_price = TRIGGER_CONDITION[order.order['order']['triggerCondition']]
      trigger_price = TRIGGER_CONDITION['DEFAULT'] unless trigger_price

      active_trades = $redis.smembers('backtest:active:trades')

      # TODO: Just be better!
      #
      # Taking a big risk here thinking we will only ever have one trade at a time.
      # I do need to know if there is a trade that could be stopped out with a STOP or LIMIT order though. If not, then we are most likely just looking to fill an order into a new trade.
      #
      # This logic can be done better. When we load the trade from active_trades.last, we should check if the STOP_LOSS or TAKE_PROFIT belongs to the trade first.
      # Don't know how we will check to see if the STOP or LIMIT orders belong to the trade as well.
      if trade.nil? && active_trades.any?
        trade = Trade.find(active_trades.last)
      end

      if trade
        type = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short
      else
        type = order.order['order']['units'].to_f > 0 ? :long : :short
      end

      case type
      when :long
        if trade.nil? && ['MARKET_IF_TOUCHED', 'LIMIT', 'STOP'].include?(order.order['order']['type'])
          # return crossed_over?(trigger_price[:long], :h, order.order['order']['price']) || crossed_over?(trigger_price[:long], :l, order.order['order']['price'])
          return crossed_over?(trigger_price[:long], nil, order.order['order']['price'])
        end

        # if trade
        #   return current_candle[trigger_price[:short]]['h'].to_f >= order.order['order']['price'].to_f if ['TAKE_PROFIT', 'MARKET_IF_TOUCHED', 'LIMIT'].include?(order.order['order']['type'])
        #   return current_candle[trigger_price[:short]]['l'].to_f <= order.order['order']['price'].to_f if ['STOP_LOSS', 'TRAILING_STOP_LOSS', 'STOP'].include?(order.order['order']['type'])
        # end

        if trade && ['STOP_LOSS', 'TRAILING_STOP_LOSS', 'STOP', 'TAKE_PROFIT', 'LIMIT', 'MARKET_IF_TOUCHED'].include?(order.order['order']['type'])
          return crossed_over?(trigger_price[:short], nil, order.order['order']['price'])
        end
      when :short
        if trade.nil? && ['MARKET_IF_TOUCHED', 'LIMIT', 'STOP'].include?(order.order['order']['type'])
          # return crossed_over?(trigger_price[:short], :h, order.order['order']['price']) || crossed_over?(trigger_price[:short], :l, order.order['order']['price'])
          return crossed_over?(trigger_price[:short], nil, order.order['order']['price'])
        end

        # if trade
        #   return current_candle[trigger_price[:long]]['l'].to_f <= order.order['order']['price'].to_f if ['TAKE_PROFIT', 'MARKET_IF_TOUCHED', 'LIMIT'].include?(order.order['order']['type'])
        #   return current_candle[trigger_price[:long]]['h'].to_f >= order.order['order']['price'].to_f if ['STOP_LOSS', 'TRAILING_STOP_LOSS', 'STOP'].include?(order.order['order']['type'])
        # end

        if trade && ['STOP_LOSS', 'TRAILING_STOP_LOSS', 'STOP', 'TAKE_PROFIT', 'LIMIT', 'MARKET_IF_TOUCHED'].include?(order.order['order']['type'])
          return crossed_over?(trigger_price[:long], nil, order.order['order']['price'])
        end
      end
    end

    # Used to determine if an order got filled into a trade or if a take profit or stop loss order of a trade got filled.
    # If we do queue_next_run it doesn't matter because we only checked for triggered orders on the first worker instance. We do this by logging backtest:last_backtest_time in redis.
    def crossed_over?(candle_type, high_low, price)
      # Using gaps in the market from the previous candle's high and low to the current incomplete candle's high and low to measure price action.
      # To enter a trade, use the prive movement from the previous candle's high and low to the current candle's high and low.
      # The current candle's high and low is set to the open of the candle to mimmic real time flow.
      return false unless current_candles[-2]
      candle_type = candle_type.to_s
      price       = price.to_f
      bottom, top = current_candles[-2][candle_type]['l'].to_f, current_candles[-2][candle_type]['h'].to_f
      bottom, top = top, bottom if bottom > top

      current_candle_high = current_candles[-1][candle_type]['h'].to_f
      current_candle_low  = current_candles[-1][candle_type]['l'].to_f
      bottom              = current_candle_low if current_candle_low < bottom
      top                 = current_candle_high if current_candle_high > top

      price >= bottom && price <= top

      # All below used current_candle as a complete candle.
      # Was only used to determine if an order got filled into a trade.

      # NOTE: Keeping this here for reference.
      # Using gaps in the previous candle to the current candle's high and low to measure price action.
      # To enter a trade, use the current candle's high and low price movement to determine if an order got triggered, 
      # including only the previous candle's high or low points when a gap in the market exists.
      #
      # return false unless current_candles[-2]
      # candle_type = candle_type.to_s
      # high_low    = high_low.to_s
      # price       = price.to_f
      # bottom, top = current_candle[candle_type]['l'].to_f, current_candle[candle_type]['h'].to_f
      # bottom, top = top, bottom if bottom > top
      #
      # previous_candle_high = current_candles[-2][candle_type]['h'].to_f
      # previous_candle_low  = current_candles[-2][candle_type]['l'].to_f
      # bottom               = previous_candle_high if previous_candle_high < bottom
      # top                  = previous_candle_low if previous_candle_low > top
      #
      # price >= bottom && price <= top

      # NOTE: Keeping this here for reference.
      # Using the highest high and lowest low between the previous and the current candle to measure price action. 2019-01-10.
      #
      # return false unless current_candles[-2]
      # candle_type = candle_type.to_s
      # high_low    = high_low.to_s
      # price       = price.to_f
      # bottom, top = current_candle[candle_type]['l'].to_f, current_candle[candle_type]['h'].to_f
      # bottom, top = top, bottom if bottom > top
      #
      # previous_candle_high = current_candles[-2][candle_type]['h'].to_f
      # previous_candle_low  = current_candles[-2][candle_type]['l'].to_f
      # bottom               = previous_candle_low if previous_candle_low < bottom
      # top                  = previous_candle_high if previous_candle_high > top
      #
      # price >= bottom && price <= top

      # NOTE: Keeping this here for reference.
      # Using only the current candle to measure price action.
      #
      # return false unless current_candle
      # candle_type = candle_type.to_s
      # high_low    = high_low.to_s
      # price       = price.to_f
      # bottom, top = current_candle[candle_type]['l'].to_f, current_candle[candle_type]['h'].to_f
      # price >= bottom && price <= top

      # NOTE: Keeping this here for reference.
      # Using the current candle and the previous candle to measure price action.
      #
      # return false unless current_candles[-2]
      # candle_type = candle_type.to_s
      # high_low    = high_low.to_s
      # price       = price.to_f
      # bottom, top = current_candles[-2][candle_type][high_low].to_f, current_candles[-1][candle_type][high_low].to_f
      # # return false if top == bottom
      # bottom, top = top, bottom if bottom > top
      # price >= bottom && price <= top
    end

    # When MARKET_ORDER, use candle ask, bid or mid price depending on the triggerCondition.
    # When any other type of order, use the price of the order itself.
    def price_on_enter(order)
      return order.order['order']['price'].to_f if order.order['order']['price']

      trigger_price = TRIGGER_CONDITION[order.order['order']['triggerCondition']]
      trigger_price = TRIGGER_CONDITION['DEFAULT'] unless trigger_price
      type          = order.order['order']['units'].to_f > 0 ? :long : :short

      current_candle[trigger_price[type]]['c'].to_f
    end

    # When TAKE_PROFIT, STOP_LOSS or TRAILING_STOP_LOSS, use the price of the order itself.
    # When closing a trade immediately, use the candle ask, bid or mid price depending on the triggerCondition.
    def price_on_exit(trade_or_type, order = nil)
      return order.order['order']['price'].to_f if order && order.order['order']['price']

      trigger_price = TRIGGER_CONDITION['DEFAULT']
      trade_or_type.is_a?(Trade) ? trade = trade_or_type : type = trade_or_type

      if trade
        type = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short
      end

      case type.to_sym
      when :long
        current_candle[trigger_price[:short]]['c'].to_f
      when :short
        current_candle[trigger_price[:long]]['c'].to_f
      end
    end

    # When MARKET_IF_TOUCHED, LIMIT, STOP, TAKE_PROFIT, STOP_LOSS or TRAILING_STOP_LOSS, use the price of the order itself.
    # When MARGIN_CLOSEOUT, use price of margin closeout level.
    # When closing a trade immediately, use the candle ask, bid or mid price depending on the triggerCondition.
    def average_close_price(options)
      order          = options[:order] if options[:order]
      price          = options[:price] if options[:price]
      trade          = options[:trade] if options[:trade]
      current_candle = options[:current_candle] if options[:current_candle]

      return order.order['order']['price'].to_f if order && order.order['order']['price']
      return price.to_f if price

      trigger_price = TRIGGER_CONDITION['DEFAULT']
      type          = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short

      case type.to_sym
      when :long
        current_candle[trigger_price[:short]]['c'].to_f
      when :short
        current_candle[trigger_price[:long]]['c'].to_f
      end

      # type = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short
      #
      # if type == :long
      #   if trade.trade['trade']['takeProfitOrder']
      #     return trade.trade['trade']['takeProfitOrder']['price'].to_f if current_candle['mid']['h'].to_f > trade.trade['trade']['takeProfitOrder']['price'].to_f
      #   end
      #
      #   if trade.trade['trade']['stopLossOrder']
      #     return trade.trade['trade']['stopLossOrder']['price'].to_f if current_candle['mid']['l'].to_f < trade.trade['trade']['stopLossOrder']['price'].to_f
      #   end
      #
      #   return current_candle['mid']['c'].to_f
      # end
      #
      # if type == :short
      #   if trade.trade['trade']['takeProfitOrder']
      #     return trade.trade['trade']['takeProfitOrder']['price'].to_f if current_candle['mid']['l'].to_f < trade.trade['trade']['takeProfitOrder']['price'].to_f
      #   end
      #
      #   if trade.trade['trade']['stopLossOrder']
      #     return trade.trade['trade']['stopLossOrder']['price'].to_f if current_candle['mid']['h'].to_f > trade.trade['trade']['stopLossOrder']['price'].to_f
      #   end
      #
      #   return current_candle['mid']['c'].to_f
      # end
    end

    # TODO: Only works for _USD pairs, remove INSTRUMENTS[instrument]['pip_price'] and include exchange rate in calculation!
    # This should only be called once or it will increase the backtest:spread:total redis key again. The key is only used for backtest display purposes and not for any calculations that would influence results.
    # If you don't supply order, you have to supply options[:price] & options[:units]
    def transaction_realized_pl(trade, order = nil, options = {})
      units      = options[:units] || ['TAKE_PROFIT', 'STOP_LOSS', 'TRAILING_STOP_LOSS'].include?(order.order['order']['type']) ? trade.trade['trade']['currentUnits'].to_f : order.order['order']['units'].to_f
      price      = options[:price] || order.order['order']['price'].to_f
      instrument = trade.trade['trade']['instrument']
      type       = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short

      case type
      when :long
        price_difference = price.to_f - trade.trade['trade']['price'].to_f
      when :short
        price_difference = trade.trade['trade']['price'].to_f - price.to_f
      end

      order_portion       = units.to_f.abs / trade.trade['trade']['initialUnits'].to_f.abs
      opening_transaction = Transaction.find(trade.id)
      entry_spread        = opening_transaction.transaction['transaction']['tradeOpened']['halfSpreadCost'].to_f * order_portion
      exit_spread         = half_spread_cost_on_exit(trade, order, options)
      spread              = (entry_spread + exit_spread).round(5)

      $redis.incrbyfloat('backtest:spread:total', spread)
      raise OandaApiV20Backtest::NotFound, "Instrument #{instrument} not found! Add #{instrument} to the INSTRUMENTS constant!" unless INSTRUMENTS[instrument]
      pip_difference = price_difference / INSTRUMENTS[instrument]['pip_size']
      (pip_difference * INSTRUMENTS[instrument]['pip_price'] * units.to_f.abs - spread).round(4)
    end

    def trade_realized_pl(trade, closing_transaction_ids, transaction_realized_pl = nil)
      trade_pl = 0.0

      closing_transaction_ids.each do |id|
        closing_transaction = Transaction.find(id)
        next unless closing_transaction
        trade_pl += closing_transaction.transaction['transaction']['pl'].to_f
      end

      trade_pl += transaction_realized_pl.to_f if transaction_realized_pl
      trade_pl
    end

    def half_spread_cost_on_enter(trade, order = nil, options = {})
      half_spread_cost_on(:enter, trade, order, options)
    end

    def half_spread_cost_on_exit(trade, order = nil, options = {})
      half_spread_cost_on(:exit, trade, order, options)
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

      # FIXME: This could fail if only options[:units] were supplied.
      instrument = trade ? trade.trade['trade']['instrument'] : order.order['order']['instrument']

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
              trade.trade['trade']['currentUnits'].to_i
            else
              order.order['order']['units'].to_i
            end
          end
      end

      pip_difference = spread_difference / INSTRUMENTS[instrument]['pip_size']
      (pip_difference * INSTRUMENTS[instrument]['pip_price'] * units).abs.round(5)
    end

    def taken_profit_or_stop_lossed(trade)
      unless trade['trade']['takeProfitOrder'] || trade.trade['trade']['stopLossOrder']
        raise OandaApiV20Backtest::TakeProfitOrStopLossNeverSet, "Trade #{trade.id} never had a take profit or stop loss set!"
      end

      trigger_price = TRIGGER_CONDITION[order.order['order']['triggerCondition']]
      trigger_price = TRIGGER_CONDITION['DEFAULT'] unless trigger_price

      type = trade.trade['trade']['initialUnits'].to_f > 0 ? :long : :short

      if type == :long
        if trade.trade['trade']['takeProfitOrder']
          # return true if current_candle[trigger_price[:short]]['h'].to_f > trade.trade['trade']['takeProfitOrder']['price'].to_f
          return true if crossed_over?(trigger_price[:short], nil, trade.trade['trade']['takeProfitOrder']['price'])
        end

        if trade.trade['trade']['stopLossOrder']
          # return true if current_candle[trigger_price[:short]]['l'].to_f < trade.trade['trade']['stopLossOrder']['price'].to_f
          return true if crossed_over?(trigger_price[:short], nil, trade.trade['trade']['stopLossOrder']['price'])
        end
      end

      if type == :short
        if trade.trade['trade']['takeProfitOrder']
          # return true if current_candle[trigger_price[:long]]['l'].to_f < trade.trade['trade']['takeProfitOrder']['price'].to_f
          return true if crossed_over?(trigger_price[:long], nil, trade.trade['trade']['takeProfitOrder']['price'])
        end

        if trade.trade['trade']['stopLossOrder']
          # return true if current_candle[trigger_price[:long]]['h'].to_f > trade.trade['trade']['stopLossOrder']['price'].to_f
          return true if crossed_over?(trigger_price[:long], nil, trade.trade['trade']['stopLossOrder']['price'])
        end
      end

      false
    end

    def conversion_pair_for(instrument, account)
      home_currency = account.account['account']['currency']
      return instrument if instrument.include?(home_currency)

      conversion_pair = nil
      base_currency   = instrument.split('_')[0]

      INSTRUMENTS.keys.each do |instrument|
        if instrument.include?(home_currency) && instrument.include?(base_currency)
          conversion_pair = instrument
          break
        end
      end

      raise OandaApiV20Backtest::Error, "Could not find conversion_pair for #{instrument}" unless conversion_pair
      conversion_pair
    end

    # TODO: Remove INSTRUMENTS[instrument]['exchange'] and include exchange rate in calculation!
    def exchange_rate_for(instrument, account)
      conversion_pair = conversion_pair_for(instrument, account)
      INSTRUMENTS[conversion_pair]['exchange'].to_f
    end

    # TODO: Only works for _USD pairs, need to allow for USD_ pairs and conversion pairs when the home currency is not part of the instrument.
    # https://www.oanda.com/forex-trading/analysis/currency-units-calculator
    def units_available(order, account)
      raise OandaApiV20Backtest::Error, "Can not calculate units available if order is not of type MARKET_IF_TOUCHED, LIMIT or STOP, order: #{order}" unless ['MARKET_IF_TOUCHED', 'LIMIT', 'STOP'].include?(order.order['order']['type'])
      trigger_price = TRIGGER_CONDITION[order.order['order']['triggerCondition']]
      trigger_price = TRIGGER_CONDITION['DEFAULT'] unless trigger_price
      type          = order.order['order']['units'].to_f > 0 ? :long : :short
      instrument    = order.order['order']['instrument']
      balance       = ENV['MARGIN_CLOSEOUT_ON_INITIAL_BALANCE'] == 'true' ? account.initial_balance.to_f : account.balance.to_f
      leverage      = account.account['account']['marginRate'].to_f
      home_currency = account.account['account']['currency']
      base_currency = instrument.split('_')[0]
      exchange_rate = home_currency == base_currency ? 1.0 : exchange_rate_for(instrument, account)
      ((balance * (1 / leverage)) / exchange_rate).floor
    end

    # FIXME: Always returns false for now. Cannot get the correct calculation working to determine the closeout price.
    #
    # TODO: Only works for _USD pairs, need to allow for USD_ pairs and conversion pairs when the home currency is not part of the instrument. Also does not work with hedge trading.
    # https://www.oanda.com/forex-trading/analysis/margin-call-calculator
    # https://oanda.secure.force.com/AnswersSupport?urlName=Forex-Margin-Formula-1436196462930&language=en_US
    # https://oanda.secure.force.com/AnswersSupport?urlName=How-to-Calculate-a-Margin-Closeout-1436196462931&language=en_US
    # http://developer.oanda.com/rest-live-v20/transaction-df/#MarketOrderMarginCloseoutReason
    # http://mini-au-pair.dk/binopt/20819-Forex+Free+Margin+Formulas-cc.html
    #
    # Oanda closes all positions at 50% margin.
    # So if you had a $10,000 account, you would be stopped out at $5,000.
    #
    # If the account currency is the same as the base of the currency pair
    #   Buy Position MR = (2m OU) / (2mb + 2m U - U)
    #   Sell Position MR = (-2m OU) / (2mb - 2m U -U)
    #
    # Account currency is the same as the quote of the currency pair
    #   Buy Position MR = (2m(OU - b)) / U(2m-1)
    #   Sell Position MR = (2m(OU + b)) / U(2m+1)
    #
    # If neither the quote nor base of the currency pair is the same as the account currency
    #   Buy Position MR = (2m(b - UOH)) / (1 - 2m)UH
    #   Sell Position MR = (2m(b + UOH)) / (1 + 2m)UH
    #
    # Where:
    #   MR = Margin Closeout Rate (Approx.)
    #   m = Margin Ratio
    #   U = Units Held
    #   O = Opening Rate of Position
    #   b = Account Balance
    #   H = Quote Home Rate
    #
    def margin_clouseout?(position, account)
      return false

      type = :long if position.position['position']['long']['units'].to_i > 0
      type = :short if position.position['position']['short']['units'].to_i < 0

      margin_closeout_rate = margin_closeout_price(position, account)

      case type
      when :long
        return [current_candles[-1]['bid']['l'].to_f, current_candles[-2]['bid']['l'].to_f].min <= margin_closeout_rate
      when :short
        return [current_candles[-1]['ask']['h'].to_f, current_candles[-2]['ask']['h'].to_f].max >= margin_closeout_rate
      end

      false
    end

    def margin_closeout_price(position, account)
      type = :long if position.position['position']['long']['units'].to_i > 0
      type = :short if position.position['position']['short']['units'].to_i < 0

      balance      = ENV['MARGIN_CLOSEOUT_ON_INITIAL_BALANCE'] == 'true' ? account.initial_balance.to_f : account.balance.to_f
      leverage     = account.account['account']['marginRate'].to_f
      margin_ratio = 100 / (leverage * 100)

      # instrument    = position.position['position']['instrument']
      # home_currency = account.account['account']['currency']
      # base_currency = instrument.split('_')[0]
      # exchange_rate = home_currency == base_currency ? 1.0 : exchange_rate_for(instrument, account)

      case type
      when :long
        position_rate        = position.position['position']['long']['averagePrice'].to_f
        units                = position.position['position']['long']['units'].to_i.abs
        margin_closeout_rate = (2 * margin_ratio * (position_rate * units - balance)) / (units * (2 * margin_ratio - 1))
      when :short
        position_rate        = position.position['position']['short']['averagePrice'].to_f
        units                = position.position['position']['short']['units'].to_i.abs
        margin_closeout_rate = (2 * margin_ratio * (position_rate * units + balance)) / (units * (2 * margin_ratio + 1))
      end

      margin_closeout_rate.round(5)
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

    # If you don't supply order, you have to supply options[:price] & options[:units].
    def trade_closed_hash(trade, order = nil, options = {})
      trade_id         = options[:id] || trade.id
      price            = options[:price] || order.order['order']['price']
      units            = options[:units] || (-trade.trade['trade']['currentUnits'].to_i)
      realized_pl      = options[:realized_pl] || transaction_realized_pl(trade, order)
      half_spread_cost = options[:half_spread_cost] || half_spread_cost_on_exit(trade, order, options)

      {
        'tradeID'                => trade_id.to_s,
        'units'                  => units.to_s,
        'price'                  => price.to_s,
        'realizedPL'             => realized_pl.to_s,
        'halfSpreadCost'         => half_spread_cost.to_s,
        'financing'              => '0.0000',
        'guaranteedExecutionFee' => '0.0000'
      }
    end

    def trade_reduced_hash(trade, order = nil, options = {})
      trade_closed_hash(trade, order, options)
    end

    private

    attr_accessor :http_verb

    def set_last_action_and_arguments(action, *args)
      self.last_action    = action.to_sym
      self.last_arguments = args
    end

    def set_http_verb(action, last_action)
      case action
      when :show
        self.http_verb = :get
      when :update, :cancel, :close
        [:configuration].include?(last_action) ? self.http_verb = :patch : self.http_verb = :put
      when :create
        self.http_verb = :post
      else
        self.http_verb = nil
      end
    end

    def set_last_transaction_id(id)
      $redis.set('backtest:last_transaction_id', id)
      self.last_transaction_id = id.to_i
    end
  end
end
