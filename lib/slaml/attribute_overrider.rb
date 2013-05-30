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
      shortcuts = {}

      attrs.each do |attr|
        name, value = attr[2].to_s, attr[3]
        # handle special haml shortcuts path
        # e.g. concat ids instead of overriding
        if attr[0] == :slaml && attr[1] == :shortattr
          shortcuts[name] = value
          next
        end

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

      shortcut_attrs = shortcuts.map do |key, value|
        [:html, :attr, key, value]
      end

      [:html, :attrs, *(shortcut_attrs + attrs.flatten(1))]
    end
  end
end
