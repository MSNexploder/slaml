module Slaml
  # This filter removes whitespace
  # @api private
  class WhitespaceRemover < Filter
    def on_slaml_whitespace(type, content)
      # TODO not sure how to handle this
      compile(content)
    end
  end
end
