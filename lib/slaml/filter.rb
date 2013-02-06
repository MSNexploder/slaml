module Slaml
  # Base class for Temple filters used in Slaml
  #
  # This base filter passes everything through and allows
  # to override only some methods without affecting the rest
  # of the expression.
  #
  # @api private
  class Filter < Temple::HTML::Filter
    # Pass-through handler
    def on_slaml_control(code, content)
      [:slaml, :control, code, compile(content)]
    end

    # Pass-through handler
    def on_slaml_embedded(type, content)
      [:slaml, :embedded, type, compile(content)]
    end

    # Pass-through handler
    def on_slaml_control(code, content)
      [:slaml, :control, code, compile(content)]
    end

    # Pass-through handler
    def on_slaml_output(code, escape, content)
      [:slaml, :output, code, escape, compile(content)]
    end
  end
end
