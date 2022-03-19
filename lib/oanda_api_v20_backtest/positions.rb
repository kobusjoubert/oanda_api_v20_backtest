# @see http://developer.oanda.com/rest-live-v20/positions-ep/
module OandaApiV20Backtest
  module Positions
    # GET /v3/accounts/:account_id/positions/:instrument
    # PUT /v3/accounts/:account_id/positions/:instrument/close
    def position(*args)
      instrument = args.shift
      options = args.shift unless args.nil? || args.empty?

      action = :show if http_verb == :get
      action = position_action_for_put(options) if http_verb == :put
      raise OandaApiV20Backtest::NoActionSet, "No action set for position #{instrument}" unless action

      # GET /v3/accounts/:account_id/positions/:instrument
      # client.account('account_id').position('EUR_USD').show
      if action == :show && instrument && !options
        position = Position.find_by_instrument(instrument)

        response = {
          'position'          => position.position['position'],
          'lastTransactionID' => last_transaction_id.to_s
        }

        return response
      end

      # PUT /v3/accounts/:account_id/positions/:instrument/close
      # client.account('account_id').position('EUR_CAD', options).close
      if action == :close && instrument && options
        response                = {}
        related_transaction_ids = []
        batch_id                = (last_transaction_id + 1).to_s
        position                = Position.find_by_instrument(instrument)
        trades_closed           = []
        total_pl                = 0.0
        i                       = 0

        i += 1

        order_create_transaction = Transaction.new(
          id:         (last_transaction_id + i).to_s,
          batch_id:   batch_id,
          account_id: account_id,
          type:       'MARKET_ORDER',
          reason:     'POSITION_CLOSEOUT',
          time:       time
        )

        if options['longUnits']
          units     = (-position.position['position']['long']['units'].to_i).to_s
          trade_ids = position.position['position']['long']['tradeIDs']
          price     = price_on_exit(:long)

          order_create_transaction.transaction['transaction']['longPositionCloseout'] = {
            'instrument' => instrument,
            'units'      => options['longUnits']
          }
        end

        if options['shortUnits']
          units     = (-position.position['position']['short']['units'].to_i).to_s
          trade_ids = position.position['position']['short']['tradeIDs']
          price     = price_on_exit(:short)

          order_create_transaction.transaction['transaction']['shortPositionCloseout'] = {
            'instrument' => instrument,
            'units'      => options['shortUnits']
          }
        end

        order_create_transaction.transaction['transaction'].merge!(
          'instrument'   => instrument,
          'units'        => units,
          'timeInForce'  => 'FOK',
          'positionFill' => 'REDUCE_ONLY'
        )

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
          reason:         'MARKET_ORDER_POSITION_CLOSEOUT',
          time:           time,
          options:        options,
          current_candle: current_candle
        )

        trade_ids.each do |id|
          trade                   = Trade.find(id)
          trade.current_candle    = current_candle
          closing_transaction_ids = (trade.trade['trade']['closingTransactionIDs'] || []) + [order_fill_transaction.id]
          units                   = (-trade.trade['trade']['currentUnits'].to_i)
          price                   = price_on_exit(trade)
          realized_pl             = transaction_realized_pl(trade, nil, units: units, price: price)
          trade_closed            = trade_closed_hash(trade, nil, price: price, units: units, realized_pl: realized_pl)
          trades_closed           << trade_closed
          total_pl                += trade_closed['realizedPL'].to_f

          trade.trade['trade'].merge!(
            'state'                 => 'CLOSED',
            'currentUnits'          => '0',
            'realizedPL'            => trade_realized_pl(trade, closing_transaction_ids.map{ |id| id unless id == order_fill_transaction.id }.compact, trade_closed['realizedPL']).to_s,
            'averageClosePrice'     => average_close_price(current_candle: current_candle, trade: trade),
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
              'tradeCloseTransactionID' => order_fill_transaction.id
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
              'tradeCloseTransactionID' => order_fill_transaction.id
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
              'tradeCloseTransactionID' => order_fill_transaction.id
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

        order_fill_transaction.transaction['transaction'].merge!(
          'instrument'     => instrument,
          'units'          => units.to_s,
          'price'          => price.to_s,
          'pl'             => total_pl.to_s,
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

        # if trade.trade['trade']['clientExtensions'] && trade.trade['trade']['clientExtensions']['id']
        #   order_fill_transaction.transaction['transaction']['tradesClosed'].first['clientTradeID'] = trade.trade['trade']['clientExtensions']['id']
        # end

        order.order['order'].merge!(
          'tradeClosedIDs'       => trade_ids,
          'fillingTransactionID' => order_fill_transaction.id,
          'state'                => 'FILLED',
          'filledTime'           => time,
          'instrument'           => instrument,
          'units'                => units.to_s,
          'timeInForce'          => 'FOK',
          'positionFill'         => 'REDUCE_ONLY'
        )

        related_transaction_ids << order_create_transaction.id
        related_transaction_ids << order_fill_transaction.id

        order_create_transaction.save
        order_fill_transaction.save
        order.save

        if options['longUnits']
          response.merge!(
            'longOrderCreateTransaction' => order_create_transaction.transaction['transaction'],
            'longOrderFillTransaction'   => order_fill_transaction.transaction['transaction']
          )
        end

        if options['shortUnits']
          response.merge!(
            'shortOrderCreateTransaction' => order_create_transaction.transaction['transaction'],
            'shortOrderFillTransaction'   => order_fill_transaction.transaction['transaction']
          )
        end

        response.merge!('lastTransactionID' => (last_transaction_id + i).to_s)
        return response
      end
    end

    private

    def position_action_for_put(options = nil)
      return :close unless options
      return :close if options['longUnits'] || options['longClientExtensions'] || options['shortUnits'] || options['shortClientExtensions']
      return nil
    end
  end
end
