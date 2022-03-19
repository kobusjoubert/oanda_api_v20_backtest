module OandaApiV20Backtest
  DRb.start_service
  $candle_server = DRbObject.new_with_uri(OandaApiV20Backtest::CandleServer::URI)
end
