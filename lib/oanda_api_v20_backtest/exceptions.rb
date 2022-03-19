module OandaApiV20Backtest
  class Error < RuntimeError; end
  class NotFound < RuntimeError; end
  class OrderNotClosed < RuntimeError; end
  class NoActionSet < RuntimeError; end
  class TakeProfitOrStopLossNeverSet < RuntimeError; end
end

module OandaApiV20
  class ApiError < RuntimeError; end
  class RequestError < RuntimeError; end
end
