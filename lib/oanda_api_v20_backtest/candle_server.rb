module OandaApiV20Backtest
  class CandleServer
    URI = 'druby://localhost:8787'

    attr_accessor :instrument, :granularity
    attr_reader   :instrument_path, :candle_index, :candles_required

    def initialize(options = {})
      options.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end

      @instrument      ||= 'WTICO_USD' # NATGAS_USD, SUGAR_USD, EUR_USD
      @granularity     ||= 'M1'
      candle_path      = ENV['CANDLE_PATH'] || "#{Dir.home}/Documents/Instruments"
      @instrument_path = "#{candle_path}/#{instrument}_#{granularity}"

      # {
      #   '2010-11-01' => { 'range' => 0..5, 'count' => 6, 'total' => 6 },
      #   '2010-11-02' => { 'range' => 6..11, 'count' => 6, 'total' => 12 }
      # }
      @candle_index = {}
      total         = 0

      Dir.entries(instrument_path).sort.each do |item|
        next if item == '.' || item == '..' || item == '.DS_Store'

        count = 0
        key   = item.split('.')[0]

        @candle_index[key] = {}

        File.open("#{instrument_path}/#{item}").each do |line|
          line_candles = JSON.parse(line)['candles']
          line_candles = line_candles.map{ |candle| candle if candle['time'].split('T')[0] == key }.compact
          count        = line_candles.count
        end

        @candle_index[key]['range'] = 0..count - 1 if total == 0
        total += count
        @candle_index[key]['range'] = (total - count)..(total - 1) if total > 0
        @candle_index[key]['count'] = count
        @candle_index[key]['total'] = total
      end
    end

    # TODO: Deprecate! Or use get_candles to return last candle.
    def get_candle(backtest_index)
      candles_for_day  = []
      candle_index_key = ''

      candle_index.each do |key, value|
        if backtest_index < value['total']
          candle_index_key = key

          File.open("#{instrument_path}/#{candle_index_key}.json").each do |line|
            line_candles    = JSON.parse(line)['candles']
            line_candles    = line_candles.map{ |candle| candle if candle['time'].split('T')[0] == key }.compact
            candles_for_day = line_candles
          end

          break
        end
      end

      current_day_index_start_at = candle_index[candle_index_key]['total'] - candle_index[candle_index_key]['count']
      candles_for_day[backtest_index - current_day_index_start_at]
    end

    def get_candles(backtest_index, count)
      candles           = []
      requested_range   = (backtest_index - count + 1)..backtest_index
      @candles_required = backtest_index unless candles_required
      @candles_required = count if count > @candles_required
      range_found       = false

      candle_index.each do |key, value|
        range = (requested_range.to_a & value['range'].to_a)

        # Delete keys from the front of the candle_index hash when no longer needed in future calls.
        if !range_found && range.empty?
          candle_index.delete(key) if count == candles_required
          next
        end

        break if range_found && range.empty?

        from = range.first - (value['total'] - value['count'])
        to   = range.last - (value['total'] - value['count'])

        File.open("#{instrument_path}/#{key}.json").each do |line|
          line_candles = JSON.parse(line)['candles']
          line_candles = line_candles.map{ |candle| candle if candle['time'].split('T')[0] == key }.compact
          candles      << line_candles[from..to]
          candles.flatten!
        end

        # Build up the candles array while the range array has values. When the range array is empty, we have all the candles we need and we can break out.
        range_found = true if count == candles.size
      end

      # Reset last/current candle to be an incomplete candle.
      # This is to mimmic the normal flow of candles, using the last/current candle as a candle that just opened after the previous candle closed.
      candles.last['complete'] = false
      candles.last['volume']   = 1
      current_mid_open         = candles.last['mid']['o'] if candles.last['mid']
      current_bid_open         = candles.last['bid']['o'] if candles.last['bid']
      current_ask_open         = candles.last['ask']['o'] if candles.last['ask']
      candles.last['mid']      = { 'o' => current_mid_open, 'h' => current_mid_open, 'l' => current_mid_open, 'c' => current_mid_open } if current_mid_open
      candles.last['bid']      = { 'o' => current_bid_open, 'h' => current_bid_open, 'l' => current_bid_open, 'c' => current_bid_open } if current_bid_open
      candles.last['ask']      = { 'o' => current_ask_open, 'h' => current_ask_open, 'l' => current_ask_open, 'c' => current_ask_open } if current_ask_open

      { 'instrument' => instrument, 'granularity' => granularity, 'candles' => candles }
    end

    # Kept here incase the improved get_candles breaks. 
    def get_candles_original(backtest_index, count)
      candles         = []
      requested_range = (backtest_index - count + 1)..backtest_index

      candle_index.each do |key, value|
        range = (requested_range.to_a & value['range'].to_a)
        next if range.empty?

        from = range.first - (value['total'] - value['count'])
        to   = range.last - (value['total'] - value['count'])

        File.open("#{instrument_path}/#{key}.json").each do |line|
          line_candles = JSON.parse(line)['candles']
          line_candles = line_candles.map{ |candle| candle if candle['time'].split('T')[0] == key }.compact
          candles      << line_candles[from..to]
        end
      end

      candles.flatten!

      { 'instrument' => instrument, 'granularity' => granularity, 'candles' => candles }
    end
  end
end
