module Slaml
  # @api private
  class ControlStructures < Filter
    define_options :disable_capture

    # Handle control expression `[:slaml, :control, code, content]`
    #
    # @param [String] code Ruby code
    # @param [Array] content Temple expression
    # @return [Array] Compiled temple expression
    def on_slaml_control(code, content)
      [:multi,
        [:code, code],
        compile(content)]
    end
  end    
end
