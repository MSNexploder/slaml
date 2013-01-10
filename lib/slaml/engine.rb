module Slaml
  # Slaml engine which transforms Haml code to executable ruby code
  # @api public
  class Engine < Temple::Engine
    define_options :pretty => false,
                   :sort_attrs => true,
                   :attr_wrapper => '"',
                   :generator => Temple::Generators::ArrayBuffer

    use Slaml::Parser, :file, :tabsize, :format, :encoding

    html :Pretty, :format, :attr_wrapper, :pretty, :indent

    filter :ControlFlow
    
    filter :MultiFlattener
    use :Optimizer do
      (options[:streaming] ? Temple::Filters::StaticMerger : Temple::Filters::DynamicInliner).new
    end
    use :Generator do
      options[:generator].new(options.to_hash.reject {|k,v| !options[:generator].default_options.valid_keys.include?(k) })
    end
  end
end
