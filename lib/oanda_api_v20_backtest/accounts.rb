# @see http://developer.oanda.com/rest-live-v20/account-ep/
module OandaApiV20Backtest
  module Accounts
    # GET /v3/accounts/:account_id
    # client.account('account_id').show
    def account(id)
      account = Account.find(id)

      response = {
        'account' => account.account['account'].merge(
          'orders' => [],
          'positions' => [],
          'trades' => [],
          'lastTransactionID' => last_transaction_id.to_s
        ),
        'lastTransactionID' => last_transaction_id.to_s
      }

      return response
    end

    # GET /v3/accounts
    # client.accounts.show
    def accounts
      account = Account.new

      response = {
        'accounts' => [
          {
            'id' => account.id,
            'tags' => []
          }
        ]
      }

      return response
    end

    # GET /v3/accounts/:account_id/summary
    # client.account('account_id').summary.show
    def summary
      account = Account.new

      response = {
        'account' => account.account['account'].merge(
          'createdByUserID' => 1,
          'createdTime' => '2016-06-16T01:00:00.000000000Z',
          'guaranteedStopLossOrderMode' => 'DISABLED',
          'lastTransactionID' => last_transaction_id.to_s
        ),
        'lastTransactionID' => last_transaction_id.to_s
      }

      return response
    end

    # GET /v3/accounts/:account_id/changes
    # client.account('account_id').changes(options).show
    def changes(options = {})
      options          = { 'sinceTransactionID' => nil } unless options['sinceTransactionID']
      since_id         = options['sinceTransactionID'].to_i
      orders_filled    = []
      orders_cancelled = []
      trades_opened    = []
      trades_reduced   = []
      trades_closed    = []
      transactions     = []

      $redis.smembers('backtest:transactions').each do |id|
        if id.to_i <= since_id
          $redis.srem('backtest:transactions', id)
          next
        end

        transaction = Transaction.find(id)
        transactions << transaction.transaction['transaction']

        # if ['LINKED_TRADE_CLOSED'].include?(transaction.transaction['transaction']['reason'])
        if ['ORDER_CANCEL'].include?(transaction.transaction['transaction']['type'])
          order = Order.find(transaction.transaction['transaction']['orderID'])

          if order.order['order']['state'] == 'CANCELLED'
            orders_cancelled << order.order['order'] unless orders_cancelled.map{ |o| o['id'] }.include?(order.id)

            # if ['LINKED_TRADE_CLOSED'].include?(transaction.transaction['transaction']['reason'])
            #   trade = Trade.find(order.order['order']['tradeID'])
            #   trades_closed << trade.trade['trade'] trades_closed.map{ |t| t['id'] }.include?(trade.id)
            # end
          end
        end

        if ['ORDER_FILL'].include?(transaction.transaction['transaction']['type'])
        # if ['MARKET_ORDER', 'MARKET_IF_TOUCHED_ORDER', 'MARKET_ORDER_POSITION_CLOSEOUT', 'MARKET_ORDER_TRADE_CLOSE', 'LIMIT_ORDER', 'STOP_ORDER', 'TAKE_PROFIT_ORDER', 'STOP_LOSS_ORDER', 'TRAILING_STOP_LOSS_ORDER'].include?(transaction.transaction['transaction']['reason'])
          order = Order.find(transaction.transaction['transaction']['orderID'])

          if order.order['order']['state'] == 'FILLED'
            orders_filled << order.order['order']

            if ['MARKET_ORDER', 'MARKET_IF_TOUCHED_ORDER', 'MARKET_ORDER_POSITION_CLOSEOUT', 'MARKET_ORDER_TRADE_CLOSE', 'LIMIT_ORDER', 'STOP_ORDER'].include?(transaction.transaction['transaction']['reason'])
              if order.order['order']['tradeOpenedID']
                trade = Trade.find(order.order['order']['tradeOpenedID'])
                trades_opened << trade.trade['trade'] unless trades_opened.map{ |t| t['id'] }.include?(trade.id)
              end

              if order.order['order']['tradeReducedID']
                trade = Trade.find(order.order['order']['tradeReducedID'])
                trades_reduced << trade.trade['trade'] unless trades_reduced.map{ |t| t['id'] }.include?(trade.id)
              end

              if order.order['order']['tradeClosedIDs']
                order.order['order']['tradeClosedIDs'].each do |id|
                  trade = Trade.find(id)
                  trades_closed << trade.trade['trade'] unless trades_closed.map{ |t| t['id'] }.include?(trade.id)
                end
              end
            end
          end
        end

        if transaction.transaction['transaction']['tradesClosed']
          transaction.transaction['transaction']['tradesClosed'].each do |closed_trade|
            trade = Trade.find(closed_trade['tradeID'])
            trades_closed << trade.trade['trade'] unless trades_closed.map{ |t| t['id'] }.include?(trade.id)
          end
        end

        if transaction.transaction['transaction']['tradeReduced']
          reduced_trade = transaction.transaction['transaction']['tradeReduced']
          trade = Trade.find(reduced_trade['tradeID'])
          trades_reduced << trade.trade['trade'] unless trades_reduced.map{ |t| t['id'] }.include?(trade.id)
        end

        if ['MARKET_ORDER'].include?(transaction.transaction['transaction']['type'])
          if ['MARGIN_CLOSEOUT'].include?(transaction.transaction['transaction']['reason'])
            $redis.smembers('backtest:margin_closeout_trades').each do |id|
              trade = Trade.find(id)
              next unless trade.trade['trade']['state'] == 'CLOSED'
              trades_closed << trade.trade['trade'] unless trades_closed.map{ |t| t['id'] }.include?(trade.id)
            end

            $redis.del('backtest:margin_closeout_trades')
          end
        end
      end

      response = {
        'changes' => {
          'ordersFilled'    => orders_filled,
          'ordersCancelled' => orders_cancelled,
          'tradesOpened'    => trades_opened,
          'tradesReduced'   => trades_reduced,
          'tradesClosed'    => trades_closed,
          'transactions'    => transactions
        },
        'state' => {
          'NAV'                        => '10000.00000',
          'marginAvailable'            => '10000.00000',
          'marginCloseoutMarginUsed'   => '10.00000',
          'marginCloseoutNAV'          => '9900.00000',
          'marginCloseoutPercent'      => '0.00005',
          'marginCloseoutUnrealizedPL' => '-0.01000',
          'marginUsed'                 => '10.00000',
          'positionValue'              => '500.00000',
          'unrealizedPL'               => '-0.01000',
          'withdrawalLimit'            => '9900.00000',
          'orders'                     => [],
          'trades'                     => [],
          'positions'                  => []
        },
        'lastTransactionID' => last_transaction_id.to_s
      }

      response
    end

    # PATCH /v3/accounts/:account_id/configuration
    # client.account('account_id').configuration(options).update
    def configuration(options = {})
      {
        'clientConfigureTransaction' => {
          'id' => '0',
          'batchID' => '0',
          'accountID' => Account::ACCOUNT_ID,
          'alias' => 'Backtesting!',
          'time' => '2016-06-16T01:00:00.000000000Z',
          'type' => 'CLIENT_CONFIGURE',
          'userID' => 1
        },
        'lastTransactionID' => last_transaction_id.to_s
      }
    end
  end
end
