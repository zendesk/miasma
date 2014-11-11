# Load in dependencies
require 'http'
require 'multi_json'
require 'multi_xml'

# Make version available
require 'miasma/version'

module Miasma
  autoload :Error, 'miasma/error'
  autoload :Models, 'miasma/models'
  autoload :Types, 'miasma/types'
  autoload :Utils, 'miasma/utils'

  # Generate and API connection
  #
  # @param args [Hash]
  # @option args [String, Symbol] :type API type (:compute, :dns, etc)
  # @option args [String, Symbol] :provider Service provider
  # @option args [Hash] :credentials Service provider credentials
  def self.api(args={})
    args = Utils::Smash.new(args)
    [:type, :provider, :credentials].each do |key|
      unless(args[key])
        raise ArgumentError.new "Missing required api argument `#{key.inspect}`!"
      end
    end
    args[:type] = Utils.camel(args[:type].to_s).to_sym
    args[:provider] = Utils.camel(args[:provider].to_s).to_sym
    begin
      require "miasma/contrib/#{Utils.snake(args[:provider])}"
    rescue LoadError
      # just ignore
    end
    base_klass = Models.const_get(args[:type])
    begin
      if(base_klass)
        api_klass = base_klass.const_get(args[:provider])
        if(api_klass)
          api_klass.new(args[:credentials].to_smash)
        else
          raise Error.new "Failed to locate #{args[:type]} API for #{args[:provider].inspect}"
        end
      else
        raise Error.new "Failed to locate request API type #{args[:type].inspect}"
      end
    rescue NameError
      raise Error.new "Failed to locate request API type #{args[:type].inspect}"
    end
  end

end
