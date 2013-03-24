module Slaml
  # Slaml engine which transforms Haml code to executable ruby code
  # @api public
  class Engine < Temple::Engine
    define_options :pretty => true,
                   :sort_attrs => true,
                   :attr_quote => "'",
                   :merge_attrs => {'class' => ' '},
                   :override_attrs => %w(id),
                   :encoding => 'utf-8',
                   :generator => Temple::Generators::ArrayBuffer

    use Slaml::Parser, :file, :escape_html, :tabsize, :format, :encoding
    use Slaml::Embedded, :enable_engines, :disable_engines, :pretty
    use Slaml::Interpolation

    use Slaml::EndInserter
    use Slaml::Controls, :disable_capture
    use Slaml::AttributeOverrider, :override_attrs
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
