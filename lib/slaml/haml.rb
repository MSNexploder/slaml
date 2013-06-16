# Quark like Haml (unless the real Haml is in the house)
unless defined?(Haml)
  require 'slaml'

  require 'slaml/haml/template'

  module Haml
    class Engine
      def initialize(template, options = {})
        @options = options.dup
        @options[:filename] ||= '__template__'
        @options[:line] ||= 0
        @template = Slaml::Template.new(slaml_options) { template }
      end

      def render(scope = Object.new, locals = {}, &block)
        @template.render(scope, locals, &block)
      end

      def def_method(object, name, *local_names)
        method = object.is_a?(Module) ? :module_eval : :instance_eval
        object.send(method, "def #{name}; (#{@template.precompiled_template}); end",
                    @options[:filename], @options[:line])
      end

      private

      def slaml_options
        {
          :pretty => !@options[:ugly],
          :format => (@options[:format] || :html5),
          :escape_html => @options[:escape_html]
        }
      end
    end
  end
end
