# Quark like Haml (unless the real Haml is in the house)
require 'slaml'

unless defined?(Haml)
  module Haml
    class Engine
      def initialize(template, options = {})
        @template = Slaml::Template.new(options) { template }
      end

      def render(scope = Object.new, locals = {}, &block)
        @template.render(scope, locals, &block)
      end
    end
  end
end
