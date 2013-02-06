module Slaml
  # This filter removes duplicate attributes
  # @api private
  class AttributeOverrider < Filter
    define_options :override_attrs => %w(id)

    def initialize(opts = {})
      super
      raise ArgumentError, "Option :override_attrs must be an Array of Strings" unless Array === options[:override_attrs] &&
        options[:override_attrs].all? {|a| String === a }
    end

    def on_html_attrs(*attrs)
      names = []
      values = {}

      attrs.each do |attr|
        name, value = attr[2].to_s, attr[3]
        if values[name]
          if options[:override_attrs].include? name
            values[name] = [value]
          else
            values[name] << value
          end
          
        else
          values[name] = [value]
          names << name
        end
      end

      attrs = names.map do |name|
        vals = values[name]
        vals.map { |v| [:html, :attr, name, v] }
      end

      [:html, :attrs, *attrs.flatten(1)]
    end
  end
end
