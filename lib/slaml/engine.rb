module Slaml
  # Slaml engine which transforms Haml code to executable ruby code
  # @api public
  class Engine < Temple::Engine
    define_options :pretty => true,
                   :sort_attrs => true,
                   :attr_quote => "'",
                   :merge_attrs => {'class' => ' ', 'id' => '_'},
                   :override_attrs => %w(id),
                   :sort_attr_keys => %(class),
                   :encoding => 'utf-8',
                   :generator => Temple::Generators::ArrayBuffer

    filter :Encoding, :encoding
    filter :RemoveBOM
    use Slaml::Parser, :file, :escape_html, :tabsize, :format
    use Slaml::Embedded, :enable_engines, :disable_engines, :pretty
    use Slaml::Interpolation

    use Slaml::EndInserter
    use Slaml::Controls, :disable_capture
    use Slaml::AttributeOverrider, :override_attrs
    use Slaml::AttributeValueSorter, :sort_attrs, :sort_attr_keys
    html :AttributeSorter, :sort_attrs
    html :AttributeMerger, :merge_attrs
    use Slaml::CodeAttributes, :merge_attrs

    html :Pretty, :format, :attr_quote, :pretty, :indent, :js_wrapper

    filter :ControlFlow
    filter :Escapable, :use_html_safe, :disable_escape

    filter :MultiFlattener
    use :Optimizer do
      (options[:streaming] ? Temple::Filters::StaticMerger : Temple::Filters::DynamicInliner).new
    end
    use :Generator do
      options[:generator].new(options.to_hash.reject {|k,v| !options[:generator].default_options.valid_keys.include?(k) })
    end
  end
end
