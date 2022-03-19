# @see http://developer.oanda.com/rest-live-v20/orders-ep/
module OandaApiV20Backtest
  module Orders
    # POST /v3/accounts/:account_id/orders
    # GET  /v3/accounts/:account_id/orders/:order_id
    # PUT  /v3/accounts/:account_id/orders/:order_id
    # PUT  /v3/accounts/:account_id/orders/:order_id/clientExtensions
    # PUT  /v3/accounts/:account_id/orders/:order_id/cancel
    def order(*args)
      id_or_options = args.shift
      id_or_options.is_a?(Hash) ? options = id_or_options : id = id_or_options
      options = args.shift unless args.nil? || args.empty?

      action = :show if http_verb == :get
      action = :create if http_verb == :post
      action = order_action_for_put(options) if http_verb == :put
      raise OandaApiV20Backtest::NoActionSet, "No action set for trade #{id}" unless action

      # POST /v3/accounts/:account_id/orders
      # client.account('account_id').order(options).create
      if action == :create && !id && options
        response                = {}
        related_transaction_ids = []
        order_type              = options['order']['type']
        batch_id                = (last_transaction_id + 1).to_s
        i                       = 0

        i += 1

        order_create_transaction = Transaction.new(
          id:             (last_transaction_id + i).to_s,
          batch_id:       batch_id,
          account_id:     account_id,
          type:           "#{order_type}_ORDER",
          reason:         'CLIENT_ORDER',
          time:           time,
          options:        options,
          current_candle: current_candle
        )

        order = Order.new(
          id:      order_create_transaction.id,
          time:    time,
          type:    order_type,
          options: options
        )

        if order_type == 'MARKET'
          i += 1

          order_fill_transaction = Transaction.new(
            id:             (last_transaction_id + i).to_s,
            batch_id:       batch_id,
            order_id:       order.id,
            account_id:     account_id,
            type:           'ORDER_FILL',
            reason:         'MARKET_ORDER',
            time:           time,
            options:        options,
            current_candle: current_candle
          )

          trade = Trade.new(
            id:             order_fill_transaction.id,
            time:           time,
            options:        options,
            current_candle: current_candle
          )

          order.order['order'].merge!(
            'tradeOpenedID'        => trade.id,
            'fillingTransactionID' => order_fill_transaction.id,
            'state'                => 'FILLED',
            'filledTime'           => time
          )

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

        related_transaction_ids << order_create_transaction.id
        related_transaction_ids << order_fill_transaction.id if order_fill_transaction

        take_profit_order.save if take_profit_order
        stop_loss_order.save if stop_loss_order
        trailing_stop_loss_order.save if trailing_stop_loss_order
        order_create_transaction.save
        order_fill_transaction.save if order_fill_transaction
        order.save
        trade.save if trade

        response['orderCreateTransaction'] = order_create_transaction.transaction['transaction']
        response['orderFillTransaction']   = order_fill_transaction.transaction['transaction'] if order_fill_transaction

        response.merge!(
          'relatedTransactionIDs' => related_transaction_ids,
          'lastTransactionID'     => related_transaction_ids.last
        )

        return response
      end

      # GET /v3/accounts/:account_id/orders/:order_id
      # client.account('account_id').order(id).show
      if action == :show && id && !options
        order = Order.find(id)

        response = {
          'order'             => order.order['order'],
          'lastTransactionID' => last_transaction_id.to_s
        }

        return response
      end

      # PUT /v3/accounts/:account_id/orders/:order_id
      # client.account('account_id').order(id, options).update
      if action == :update && id && options && options['order']
        response                = {}
        related_transaction_ids = []
        order_type              = options['order']['type']
        batch_id                = (last_transaction_id + 1).to_s
        order_cancelled         = Order.find(id)

        order_cancel_transaction = Transaction.new(
          id:         (last_transaction_id + 1).to_s,
          order_id:   order_cancelled.id,
          batch_id:   batch_id,
          account_id: account_id,
          type:       'ORDER_CANCEL',
          reason:     'CLIENT_REQUEST_REPLACED',
          time:       time,
          options:    options
        )

        order_cancel_transaction.transaction['transaction']['replacedByOrderID'] = (last_transaction_id + 2).to_s

        order_cancelled.order['order'].merge!(
          'state'                   => 'CANCELLED',
          'cancellingTransactionID' => order_cancel_transaction.id,
          'replacedByOrderID'       => (last_transaction_id + 2).to_s,
          'cancelledTime'           => time
        )

        order_create_transaction = Transaction.new(
          id:         (last_transaction_id + 2).to_s,
          batch_id:   batch_id,
          account_id: account_id,
          type:       "#{order_type}_ORDER",
          reason:     'REPLACEMENT',
          time:       time,
          options:    options
        )

        order_create_transaction.transaction['transaction']['replacesOrderID'] = order_cancelled.id

        order_created = Order.new(
          id:      order_create_transaction.id,
          time:    time,
          type:    order_type,
          options: options
        )

        order_created.order['order']['replacesOrderID'] = order_cancelled.id

        related_transaction_ids << order_cancel_transaction.id
        related_transaction_ids << order_create_transaction.id

        order_cancel_transaction.save
        order_create_transaction.save
        order_cancelled.save
        order_created.save

        response.merge!(
          'orderCancelTransaction' => order_cancel_transaction.transaction['transaction'],
          'orderCreateTransaction' => order_create_transaction.transaction['transaction'],
          'relatedTransactionIDs'  => related_transaction_ids,
          'lastTransactionID'      => related_transaction_ids.last
        )

        return response
      end

      # PUT /v3/accounts/:account_id/orders/:order_id/clientExtensions
      # client.account('account_id').order(id, options).update
      if action == :update && id && options && (options['clientExtensions'] || options['tradeClientExtensions'])
        response                = {}
        related_transaction_ids = []
        batch_id                = (last_transaction_id + 1).to_s
        order                   = Order.find(id)

        transaction = Transaction.new(
          id:         (last_transaction_id + 1).to_s,
          order_id:   order.id,
          batch_id:   batch_id,
          account_id: account_id,
          type:       'ORDER_CLIENT_EXTENSIONS_MODIFY',
          time:       time,
          options:    options
        )

        if options['clientExtensions']
          order.order['order']['clientExtensions'] = options['clientExtensions']
        end

        if options['tradeClientExtensions']
          order.order['order']['tradeClientExtensions'] = options['tradeClientExtensions']
        end

        related_transaction_ids << transaction.id

        transaction.save
        order.save

        response.merge!(
          'orderClientExtensionsModifyTransaction' => transaction.transaction['transaction'],
          'relatedTransactionIDs'                  => related_transaction_ids,
          'lastTransactionID'                      => related_transaction_ids.last
        )

        return response
      end

      # PUT /v3/accounts/:account_id/orders/:order_id/cancel
      # client.account('account_id').order(id).cancel
      if action == :cancel && id && !options
        response                = {}
        related_transaction_ids = []
        batch_id                = (last_transaction_id + 1).to_s
        order                   = Order.find(id)

        transaction = Transaction.new(
          id:         (last_transaction_id + 1).to_s,
          order_id:   order.id,
          batch_id:   batch_id,
          account_id: account_id,
          type:       'ORDER_CANCEL',
          reason:     'CLIENT_REQUEST',
          time:       time,
          options:    options
        )

        order.order['order'].merge!(
          'state'                   => 'CANCELLED',
          'cancellingTransactionID' => transaction.id,
          'cancelledTime'           => time
        )

        # transaction.transaction['transaction']['clientOrderID'] = '' # TODO: Implement when needed.
        # transaction.transaction['transaction']['replacedByOrderID'] = '' # TODO: Implement when needed.

        related_transaction_ids << transaction.id

        transaction.save
        order.save

        response.merge!(
          'orderCancelTransaction' => transaction.transaction['transaction'],
          'relatedTransactionIDs'  => related_transaction_ids,
          'lastTransactionID'      => related_transaction_ids.last
        )

        return response
      end
    end

    # GET /v3/accounts/:account_id/orders
    # client.account('account_id').orders(options).show
    def orders(options = {})
      orders     = []
      i          = 0
      count      = (options['count'] || 50).to_i
      count      = 500 if count > 500
      state      = options['state'] || 'PENDING'
      ids        = options['ids'].split(',') if options['ids']
      before_id  = options['beforeID'].to_i if options['beforeID']
      instrument = options['instrument']

      if state == 'PENDING'
        $redis.smembers('backtest:active:orders').each do |order_id|
          next if before_id && before_id < order_id
          next if ids && !ids.include?(order_id.to_s)
          order = Order.find(order_id)
          next unless order.order['order']['state'] == state
          next unless order.order['order']['instrument'] == instrument
          orders << order.order['order']
        end
      else
        # NOTE: Redis scan can return duplicate records.
        # $redis.scan_each(match: 'backtest:order:*') do |key|
        $redis.keys('backtest:order:*').sort.reverse.each do |key|
          break if i >= count
          order_id = key.split(':').last.to_i
          next if before_id && before_id < order_id
          next if ids && !ids.include?(order_id.to_s)
          order = Order.find(order_id)
          next unless order.order['order']['state'] == state
          next unless order.order['order']['instrument'] == instrument
          orders << order.order['order']
          i += 1
        end
      end

      response = {
        'orders'            => orders,
        'lastTransactionID' => last_transaction_id.to_s
      }
    end

    # GET /v3/accounts/:account_id/pendingOrders
    # client.account('account_id').pending_orders.show
    def pending_orders
      orders = []

      $redis.smembers('backtest:active:orders').each do |id|
        orders << Order.find(id).order['order']
      end

      response = {
        'orders'            => orders,
        'lastTransactionID' => last_transaction_id.to_s
      }
    end

    private

    def order_action_for_put(options = nil)
      return :cancel unless options
      return :update if options['clientExtensions'] || options['tradeClientExtensions']
      return :update if options['order']
      return nil
    end
  end
end
