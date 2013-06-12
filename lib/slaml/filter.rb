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
    def on_slaml_text(content)
      [:slaml, :text, compile(content)]
    end

    # Pass-through handler
    def on_slaml_embedded(type, content)
      [:slaml, :embedded, type, compile(content)]
    end

    # Pass-through handler
    def on_slaml_output(escape, code, content)
      [:slaml, :output, escape, code, compile(content)]
    end

    # Pass-through handler
    def on_slaml_whitespace(type, content)
      [:slaml, :whitespace, type, compile(content)]
    end

    # Pass-through handler
    def on_slaml_text(content)
      [:slaml, :text, compile(content)]
    end
  end
end
