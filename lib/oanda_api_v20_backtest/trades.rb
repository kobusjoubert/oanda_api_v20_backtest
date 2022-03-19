# @see http://developer.oanda.com/rest-live-v20/trades-ep/
module OandaApiV20Backtest
  module Trades
    # GET /v3/accounts/:account_id/trades/:trade_id
    # PUT /v3/accounts/:account_id/trades/:trade_id/orders
    # PUT /v3/accounts/:account_id/trades/:trade_id/clientExtensions
    # PUT /v3/accounts/:account_id/trades/:trade_id/close
    def trade(*args)
      id                   = args.shift
      options              = args.shift unless args.nil? || args.empty?
      trade                = Trade.find(id)
      trade.current_candle = current_candle

      action = :show if http_verb == :get
      action = trade_action_for_put(options) if http_verb == :put
      raise OandaApiV20Backtest::NoActionSet, "No action set for trade #{id}" unless action

      # GET /v3/accounts/:account_id/trades/:trade_id
      # client.account('account_id').trade(id).show
      if action == :show && id && !options
        if (trade['trade']['takeProfitOrder'] || trade['trade']['stopLossOrder']) && taken_profit_or_stop_lossed(trade)
          raise OandaApiV20::RequestError, "An error as occured while processing response. Status 404\n{\"lastTransactionID\":\"#{last_transaction_id}\",\"errorMessage\":\"The trade ID specified does not exist\",\"errorCode\":\"NO_SUCH_TRADE\"}"
        end

        response = {
          'trade'             => trade.trade['trade'],
          'lastTransactionID' => last_transaction_id.to_s
        }

        return response
      end

      # PUT /v3/accounts/:account_id/trades/:trade_id/orders
      # client.account('account_id').trade(id, options).update
      if action == :update && id && options && (options['takeProfit'] || options['stopLoss'] || options['trailingStopLoss'])
        response                = {}
        related_transaction_ids = []
        batch_id                = (last_transaction_id + 1).to_s
        i                       = 0

        if options['takeProfit']
          if trade.trade['trade']['takeProfitOrder']
            i += 1

            cancel_take_profit_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['takeProfitOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'CLIENT_REQUEST_REPLACED',
              time:       time,
              options:    options
            )

            cancel_take_profit_transaction.transaction['transaction'].merge!(
              'replacedByOrderID' => (cancel_take_profit_transaction.id.to_i + 1).to_s
            )

            cancelled_take_profit_order = Order.find(cancel_take_profit_transaction.order_id)

            cancelled_take_profit_order.order['order'].merge!(
              'replacedByOrderID'       => cancel_take_profit_transaction.transaction['transaction']['replacedByOrderID'],
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_take_profit_transaction.id,
              'cancelledTime'           => time
            )
          end

          i += 1

          take_profit_transaction = Transaction.new(
            id:         (last_transaction_id + i).to_s,
            trade_id:   trade.id,
            batch_id:   batch_id,
            account_id: account_id,
            type:       'TAKE_PROFIT_ORDER',
            reason:     'CLIENT_ORDER',
            time:       time,
            options:    options
          )

          take_profit_order = Order.new(
            id:       take_profit_transaction.id,
            trade_id: trade.id,
            time:     time,
            type:     'TAKE_PROFIT',
            options:  options
          )

          if trade.trade['trade']['takeProfitOrder']
            take_profit_transaction.transaction['transaction'].merge!(
              'reason'                  => 'REPLACEMENT',
              'replacesOrderID'         => cancel_take_profit_transaction.order_id,
              'cancellingTransactionID' => cancel_take_profit_transaction.id
            )

            take_profit_order.order['order'].merge!(
              'replacesOrderID' => cancel_take_profit_transaction.order_id
            )
          end

          trade.trade['trade']['takeProfitOrder'] = take_profit_order.order['order']
        end

        if options['stopLoss']
          if trade.trade['trade']['stopLossOrder']
            i += 1

            cancel_stop_loss_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['stopLossOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'CLIENT_REQUEST_REPLACED',
              time:       time,
              options:    options
            )

            cancel_stop_loss_transaction.transaction['transaction'].merge!(
              'replacedByOrderID' => (cancel_stop_loss_transaction.id.to_i + 1).to_s
            )

            cancelled_stop_loss_order = Order.find(cancel_stop_loss_transaction.order_id)

            cancelled_stop_loss_order.order['order'].merge!(
              'replacedByOrderID'       => cancel_stop_loss_transaction.transaction['transaction']['replacedByOrderID'],
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_stop_loss_transaction.id,
              'cancelledTime'           => time
            )
          end

          i += 1

          stop_loss_transaction = Transaction.new(
            id:         (last_transaction_id + i).to_s,
            trade_id:   trade.id,
            batch_id:   batch_id,
            account_id: account_id,
            type:       'STOP_LOSS_ORDER',
            reason:     'CLIENT_ORDER',
            time:       time,
            options:    options
          )

          stop_loss_order = Order.new(
            id:       stop_loss_transaction.id,
            trade_id: trade.id,
            time:     time,
            type:     'STOP_LOSS',
            options:  options
          )

          if trade.trade['trade']['stopLossOrder']
            stop_loss_transaction.transaction['transaction'].merge!(
              'reason'                  => 'REPLACEMENT',
              'replacesOrderID'         => cancel_stop_loss_transaction.order_id,
              'cancellingTransactionID' => cancel_stop_loss_transaction.id
            )

            stop_loss_order.order['order'].merge!(
              'replacesOrderID' => cancel_stop_loss_transaction.order_id
            )
          end

          trade.trade['trade']['stopLossOrder'] = stop_loss_order.order['order']
        end

        if options['trailingStopLoss']
          if trade.trade['trade']['trailingStopLossOrder']
            i += 1

            cancel_trailing_stop_loss_transaction = Transaction.new(
              id:         (last_transaction_id + i).to_s,
              order_id:   trade.trade['trade']['trailingStopLossOrder']['id'],
              batch_id:   batch_id,
              account_id: account_id,
              type:       'ORDER_CANCEL',
              reason:     'CLIENT_REQUEST_REPLACED',
              time:       time,
              options:    options
            )

            cancel_trailing_stop_loss_transaction.transaction['transaction'].merge!(
              'replacedByOrderID' => (cancel_trailing_stop_loss_transaction.id.to_i + 1).to_s
            )

            cancelled_trailing_stop_loss_order = Order.find(cancel_trailing_stop_loss_transaction.order_id)

            cancelled_trailing_stop_loss_order.order['order'].merge!(
              'replacedByOrderID'       => cancel_trailing_stop_loss_transaction.transaction['transaction']['replacedByOrderID'],
              'state'                   => 'CANCELLED',
              'cancellingTransactionID' => cancel_trailing_stop_loss_transaction.id,
              'cancelledTime'           => time
            )
          end

          i += 1

          trailing_stop_loss_transaction = Transaction.new(
            id:         (last_transaction_id + i).to_s,
            trade_id:   trade.id,
            batch_id:   batch_id,
            account_id: account_id,
            type:       'TRAILING_STOP_LOSS_ORDER',
            reason:     'CLIENT_ORDER',
            time:       time,
            options:    options
          )

          trailing_stop_loss_order = Order.new(
            id:       trailing_stop_loss_transaction.id,
            trade_id: trade.id,
            time:     time,
            type:     'TRAILING_STOP_LOSS',
            options:  options
          )

          if trade.trade['trade']['trailingStopLossOrder']
            trailing_stop_loss_transaction.transaction['transaction'].merge!(
              'reason'                  => 'REPLACEMENT',
              'replacesOrderID'         => cancel_trailing_stop_loss_transaction.order_id,
              'cancellingTransactionID' => cancel_trailing_stop_loss_transaction.id
            )

            trailing_stop_loss_order.order['order'].merge!(
              'replacesOrderID' => cancel_trailing_stop_loss_transaction.order_id
            )
          end

          trade.trade['trade']['trailingStopLossOrder'] = trailing_stop_loss_order.order['order']
        end

        if cancel_take_profit_transaction
          related_transaction_ids << cancel_take_profit_transaction.id
          response['takeProfitOrderCancelTransaction'] = cancel_take_profit_transaction.transaction['transaction']
          cancel_take_profit_transaction.save
        end

        if take_profit_transaction
          related_transaction_ids << take_profit_transaction.id
          response['takeProfitOrderTransaction'] = take_profit_transaction.transaction['transaction']
          take_profit_transaction.save
        end

        if cancel_stop_loss_transaction
          related_transaction_ids << cancel_stop_loss_transaction.id
          response['stopLossOrderCancelTransaction'] = cancel_stop_loss_transaction.transaction['transaction']
          cancel_stop_loss_transaction.save
        end

        if stop_loss_transaction
          related_transaction_ids << stop_loss_transaction.id
          response['stopLossOrderTransaction'] = stop_loss_transaction.transaction['transaction']
          stop_loss_transaction.save
        end

        if cancel_trailing_stop_loss_transaction
          related_transaction_ids << cancel_trailing_stop_loss_transaction.id
          response['trailingStopLossOrderCancelTransaction'] = cancel_trailing_stop_loss_transaction.transaction['transaction']
          cancel_trailing_stop_loss_transaction.save
        end

        if trailing_stop_loss_transaction
          related_transaction_ids << trailing_stop_loss_transaction.id
          response['trailingStopLossOrderTransaction'] = trailing_stop_loss_transaction.transaction['transaction']
          trailing_stop_loss_transaction.save
        end

        cancelled_take_profit_order.save if cancelled_take_profit_order
        take_profit_order.save if take_profit_order
        cancelled_stop_loss_order.save if cancelled_stop_loss_order
        stop_loss_order.save if stop_loss_order
        cancelled_trailing_stop_loss_order.save if cancelled_trailing_stop_loss_order
        trailing_stop_loss_order.save if trailing_stop_loss_order
        trade.save

        response.merge!(
          'relatedTransactionIDs' => related_transaction_ids,
          'lastTransactionID'     => related_transaction_ids.last
        )

        return response
      end

      # PUT /v3/accounts/:account_id/trades/:trade_id/clientExtensions
      # client.account('account_id').trade(id, options).update
      if action == :update && id && options && options['clientExtensions']
        response                = {}
        related_transaction_ids = []
        batch_id                = (last_transaction_id + 1).to_s

        transaction = Transaction.new(
          id:         (last_transaction_id + 1).to_s,
          trade_id:   trade.id,
          batch_id:   batch_id,
          account_id: account_id,
          type:       'TRADE_CLIENT_EXTENSIONS_MODIFY',
          time:       time,
          options:    options
        )

        if options['clientExtensions']
          trade.trade['trade']['clientExtensions'] = options['clientExtensions']
        end

        related_transaction_ids << transaction.id

        transaction.save
        trade.save

        response.merge!(
          'tradeClientExtensionsModifyTransaction' => transaction.transaction['transaction'],
          'relatedTransactionIDs'                  => related_transaction_ids,
          'lastTransactionID'                      => related_transaction_ids.last
        )

        return response
      end

      # PUT /v3/accounts/:account_id/trades/:trade_id/close
      # client.account('account_id').trade(id).close
      if action == :close && id && !options
        response                = {}
        related_transaction_ids = []
        trades_closed           = []
        batch_id                = (last_transaction_id + 1).to_s
        units                   = (-trade.trade['trade']['currentUnits'].to_i)
        price                   = price_on_exit(trade)
        i                       = 0

        i += 1

        order_create_transaction = Transaction.new(
          id:         (last_transaction_id + i).to_s,
          batch_id:   batch_id,
          account_id: account_id,
          type:       'MARKET_ORDER',
          reason:     'TRADE_CLOSE',
          time:       time
        )

        order_create_transaction.transaction['transaction'].merge!(
          'instrument'   => trade.trade['trade']['instrument'],
          'units'        => units.to_s,
          'timeInForce'  => 'FOK',
          'positionFill' => 'REDUCE_ONLY',
          'tradeClose'   => {
            'units'   => 'ALL',
            'tradeID' => trade.id,
          }
        )

        if trade.trade['trade']['clientExtensions'] && trade.trade['trade']['clientExtensions']['id']
          order_create_transaction.transaction['transaction']['tradeClose']['clientTradeID'] = trade.trade['trade']['clientExtensions']['id']
        end

        order = Order.new(
          id:   order_create_transaction.id,
          time: time,
          type: 'MARKET'
        )

        i += 1

        order_fill_transaction = Transaction.new(
          id:             (last_transaction_id + i).to_s,
          batch_id:       batch_id,
          order_id:       order.id,
          account_id:     account_id,
          type:           'ORDER_FILL',
          reason:         'MARKET_ORDER_TRADE_CLOSE',
          time:           time,
          current_candle: current_candle
        )

        realized_pl   = transaction_realized_pl(trade, nil, units: units, price: price)
        trade_closed  = trade_closed_hash(trade, nil, units: units, price: price, realized_pl: realized_pl)
        trades_closed << trade_closed

        order_fill_transaction.transaction['transaction'].merge!(
          'instrument'     => trade.trade['trade']['instrument'],
          'units'          => units.to_s,
          'price'          => price.to_s,
          'pl'             => realized_pl.to_s,
          'financing'      => '0.0000',
          'commission'     => '0.0000',
          'accountBalance' => '1.0000',
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

        if trade.trade['trade']['clientExtensions'] && trade.trade['trade']['clientExtensions']['id']
          order_fill_transaction.transaction['transaction']['tradesClosed'].first['clientTradeID'] = trade.trade['trade']['clientExtensions']['id']
        end

        order.order['order'].merge!(
          'tradeClosedIDs'       => [trade.id],
          'fillingTransactionID' => order_fill_transaction.id.to_s,
          'state'                => 'FILLED',
          'filledTime'           => time,
          'instrument'           => trade.trade['trade']['instrument'],
          'units'                => units.to_s,
          'timeInForce'          => 'FOK',
          'positionFill'         => 'REDUCE_ONLY'
        )

        closing_transaction_ids = (trade.trade['trade']['closingTransactionIDs'] || []) + [order_fill_transaction.id]

        trade.trade['trade'].merge!(
          'state'                 => 'CLOSED',
          'currentUnits'          => '0',
          'realizedPL'            => order_fill_transaction.transaction['transaction']['pl'].to_s,
          'averageClosePrice'     => order_fill_transaction.transaction['transaction']['price'].to_s,
          'closingTransactionIDs' => closing_transaction_ids,
          'closeTime'             => time,
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
            'closedTradeID'           => trade.id.to_s,
            'tradeCloseTransactionID' => order_fill_transaction.id.to_s
          )

          cancelled_take_profit_order = Order.find(cancel_take_profit_transaction.order_id)

          cancelled_take_profit_order.order['order'].merge!(
            'state'                   => 'CANCELLED',
            'cancellingTransactionID' => cancel_take_profit_transaction.id.to_s,
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
            'closedTradeID'           => trade.id.to_s,
            'tradeCloseTransactionID' => order_fill_transaction.id.to_s
          )

          cancelled_stop_loss_order = Order.find(cancel_stop_loss_transaction.order_id)

          cancelled_stop_loss_order.order['order'].merge!(
            'state'                   => 'CANCELLED',
            'cancellingTransactionID' => cancel_stop_loss_transaction.id.to_s,
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
            'closedTradeID'           => trade.id.to_s,
            'tradeCloseTransactionID' => order_fill_transaction.id.to_s
          )

          cancelled_trailing_stop_loss_order = Order.find(cancel_trailing_stop_loss_transaction.order_id)

          cancelled_trailing_stop_loss_order.order['order'].merge!(
            'state'                   => 'CANCELLED',
            'cancellingTransactionID' => cancel_trailing_stop_loss_transaction.id.to_s,
            'cancelledTime'           => time
          )

          trade.trade['trade']['trailingStopLossOrder'] = cancelled_trailing_stop_loss_order.order['order']
        end

        related_transaction_ids << order_create_transaction.id
        related_transaction_ids << order_fill_transaction.id

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
        order_create_transaction.save
        order_fill_transaction.save
        order.save
        trade.save

        response.merge!(
          'orderCreateTransaction' => order_create_transaction.transaction['transaction'],
          'orderFillTransaction'   => order_fill_transaction.transaction['transaction'],
          'relatedTransactionIDs'  => related_transaction_ids,
          'lastTransactionID'      => related_transaction_ids.last.to_s
        )

        return response
      end
    end

    # GET /v3/accounts/:account_id/trades
    # client.account('account_id').trades(options).show
    def trades(options)
      trades     = []
      i          = 0
      count      = (options['count'] || 50).to_i
      count      = 500 if count > 500
      state      = options['state'] || 'OPEN'
      ids        = options['ids'].split(',') if options['ids']
      before_id  = options['beforeID'].to_i if options['beforeID']
      instrument = options['instrument']

      if state == 'OPEN'
        $redis.smembers('backtest:active:trades').each do |trade_id|
          next if before_id && before_id < trade_id
          next if ids && !ids.include?(trade_id.to_s)
          trade = Trade.find(trade_id)
          next unless trade.trade['trade']['state'] == state
          next unless trade.trade['trade']['instrument'] == instrument
          trades << trade.trade['trade']
        end
      else
        # NOTE: Redis scan can return duplicate records.
        # $redis.scan_each(match: 'backtest:trade:*') do |key|
        $redis.keys('backtest:trade:*').sort.reverse.each do |key|
          break if i >= count
          trade_id = key.split(':').last.to_i
          next if before_id && before_id < trade_id
          next if ids && !ids.include?(trade_id.to_s)
          trade = Trade.find(trade_id)
          next unless trade.trade['trade']['state'] == state
          next unless trade.trade['trade']['instrument'] == instrument
          trades << trade.trade['trade']
          i += 1
        end
      end

      response = {
        'trades'            => trades,
        'lastTransactionID' => last_transaction_id.to_s
      }
    end

    # GET /v3/accounts/:account_id/openTrades
    # client.account('account_id').open_trades.show
    def open_trades
      trades = []

      $redis.smembers('backtest:active:trades').each do |id|
        trades << Trade.find(id).trade['trade']
      end

      response = {
        'trades'            => trades,
        'lastTransactionID' => last_transaction_id.to_s
      }
    end

    private

    def trade_action_for_put(options = nil)
      return :close unless options
      return :update if options['clientExtensions']
      return :update if options['takeProfit'] || options['stopLoss'] || options['trailingStopLoss']
      return :close if options['units']
      return nil
    end
  end
end
