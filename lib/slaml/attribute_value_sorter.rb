module Slaml
  # This filter sorts html attribute values
  # @api private
  class AttributeValueSorter < Filter
    define_options :sort_attrs => true,
                   :sort_attr_keys => %w(class)

    def call(exp)
      options[:sort_attrs] ? super : exp
    end

    def on_html_attrs(*attrs)
      n = 0 # Use n to make sort stable. This is important because the merger could be executed afterwards.
      sort_attrs = []
      passthrough_attrs = []

      attrs.each do |attr|
        raise(InvalidExpression, 'Attribute is not a html attr') if attr[0] != :html || attr[1] != :attr
        if options[:sort_attr_keys].include? attr[2].to_s
          sort_attrs << attr
        else
          passthrough_attrs << attr
        end
      end

      [:html, :attrs, *passthrough_attrs, *sort_attrs.sort_by { |attr| [attr[3].to_s, n += 1] }]
    end
  end
end
