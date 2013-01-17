module Slaml
  # Slaml engine which transforms Haml code to executable ruby code
  # @api public
  class Engine < Temple::Engine
    define_options :pretty => false,
                   :sort_attrs => true,
                   :attr_wrapper => "'",
                   :generator => Temple::Generators::ArrayBuffer

    use Slaml::Parser, :file, :escape_html, :tabsize, :format, :encoding

    use Slaml::EndInserter
    use Slaml::ControlStructures, :disable_capture

    html :Pretty, :format, :attr_wrapper, :pretty, :indent

    html :AttributeSorter, :sort_attrs

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
