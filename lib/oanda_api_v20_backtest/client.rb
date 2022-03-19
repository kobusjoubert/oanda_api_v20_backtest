module OandaApiV20Backtest
  class Client
    attr_accessor :backtest_index, :backtest_time

    def initialize(options = {})
      options.each do |key, value|
        self.send("#{key}=", value) if self.respond_to?("#{key}=")
      end
    end

    def method_missing(name, *args, &block)
      case name
      when *Api.api_methods
        api_attributes = {
          client:              self,
          last_action:         name,
          last_arguments:      args,
          backtest_index:      backtest_index,
          backtest_time:       backtest_time
        }

        api_attributes.merge!(account_id: args.first) if name == :account
        api_attributes.merge!(instrument: args.first) if name == :instrument

        Api.new(api_attributes)
      else
        super
      end
    end
  end
end
