module Slaml
  # @api private
  class TextCollector < Filter
    def call(exp)
      @collected = ''
      super(exp)
      @collected
    end

    def on_slaml_interpolate(text)
      @collected << text
      nil
    end
  end

  # @api private
  class NewlineCollector < Filter
    def call(exp)
      @collected = [:multi]
      super(exp)
      @collected
    end

    def on_newline
      @collected << [:newline]
      nil
    end
  end

  # @api private
  class OutputProtector < Filter
    def call(exp)
      @protect = []
      @collected = ''
      super(exp)
      @collected
    end

    def on_static(text)
      @collected << text
      nil
    end

    def on_slaml_output(escape, text, content)
      @collected << "pro#{@protect.size}tect"
      @protect << [:slaml, :output, escape, text, content]
      nil
    end

    def unprotect(text)
      block = [:multi]
      while text =~ /pro(\d+)tect/
        block << [:static, $`]
        block << @protect[$1.to_i]
        text = $'
      end
      block << [:static, text]
    end
  end

  # Temple filter which processes embedded engines
  # @api private
  class Embedded < Filter
    @engines = {}

    # Register embedded engine
    #
    # @param [String] name Name of the engine
    # @param [Class]  klass Engine class
    # @param option_filter List of options to pass to engine.
    #                      Last argument can be default option hash.
    def self.register(name, klass, *option_filter)
      name = name.to_sym
      local_options = option_filter.last.respond_to?(:to_hash) ? option_filter.pop.to_hash : {}
      define_options(name, *option_filter)
      klass.define_options(name)
      @engines[name.to_sym] = proc do |options|
        klass.new({}.update(options).delete_if {|k,v| !option_filter.include?(k) && k != name }.update(local_options))
      end
    end

    def self.create(name, options)
      constructor = @engines[name] || raise(Temple::FilterError, "Embedded engine #{name} not found")
      constructor.call(options)
    end

    define_options :enable_engines, :disable_engines

    def initialize(opts = {})
      super
      @engines = {}
      @enabled = normalize_engine_list(options[:enable_engines])
      @disabled = normalize_engine_list(options[:disable_engines])
    end

    def on_slaml_embedded(name, body)
      name = name.to_sym
      raise(Temple::FilterError, "Embedded engine #{name} is disabled") unless enabled?(name)
      @engines[name] ||= self.class.create(name, options)
      @engines[name].on_slaml_embedded(name, body)
    end

    def enabled?(name)
      (!@enabled || @enabled.include?(name)) &&
        (!@disabled || !@disabled.include?(name))
    end

    protected

    def normalize_engine_list(list)
      raise(ArgumentError, "Option :enable_engines/:disable_engines must be String or Symbol list") unless !list || Array === list
      list ? list.map {|s| s.to_sym } : list
    end

    class Engine < Filter
      protected

      def collect_text(body)
        @text_collector ||= TextCollector.new
        @text_collector.call(body)
      end

      def collect_newlines(body)
        @newline_collector ||= NewlineCollector.new
        @newline_collector.call(body)
      end
    end

    # Basic tilt engine
    class TiltEngine < Engine
      def on_slaml_embedded(engine, body)
        tilt_engine = Tilt[engine] || raise(Temple::FilterError, "Tilt engine #{engine} is not available.")
        tilt_options = options[engine.to_sym] || {}
        [:multi, tilt_render(tilt_engine, tilt_options, collect_text(body)), collect_newlines(body)]
      end
    end

    # Tilt-based static template (evaluated at compile-time)
    class StaticTiltEngine < TiltEngine
      protected

      def tilt_render(tilt_engine, tilt_options, text)
        [:static, tilt_engine.new(tilt_options) { text }.render]
      end
    end

    # Sass engine which supports :pretty option
    class SassEngine < TiltEngine
      define_options :pretty

      protected

      def tilt_render(tilt_engine, tilt_options, text)
        text = tilt_engine.new(tilt_options.merge(
          :style => options[:pretty] ? :expanded : :compressed,
          :cache => false)) { text }.render
        text.chomp!
        [:static, text]
      end
    end

    # Tilt-based engine which is precompiled
    class PrecompiledTiltEngine < TiltEngine
      protected

      def tilt_render(tilt_engine, tilt_options, text)
        # HACK: Tilt::Engine#precompiled is protected
        [:dynamic, tilt_engine.new(tilt_options) { text }.send(:precompiled, {}).first]
      end
    end

    # Static template with interpolated ruby code
    class InterpolateTiltEngine < TiltEngine
      def collect_text(body)
        output_protector.call(interpolation.call(body))
      end

      def tilt_render(tilt_engine, tilt_options, text)
        output_protector.unprotect(tilt_engine.new(tilt_options) { text }.render)
      end

      private

      def interpolation
        @interpolation ||= Interpolation.new
      end

      def output_protector
        @output_protector ||= OutputProtector.new
      end
    end

    # ERB engine (uses the Temple ERB implementation)
    class ERBEngine < Engine
      def on_slaml_embedded(engine, body)
        [:multi, [:newline], erb_parser.call(collect_text(body))]
      end

      protected

      def erb_parser
        @erb_parser ||= Temple::ERB::Parser.new
      end
    end

    # Tag wrapper engine
    # Generates a html tag and wraps another engine (specified via :engine option)
    class TagEngine < Engine
      disable_option_validator!

      def on_slaml_embedded(engine, body)
        if options[:engine]
          opts = {}.update(options)
          opts.delete(:engine)
          opts.delete(:tag)
          opts.delete(:attributes)
          @engine ||= options[:engine].new(opts)
          body = @engine.on_slaml_embedded(engine, body)
        end
        [:html, :tag, options[:tag], [:html, :attrs, *options[:attributes].map {|k, v| [:html, :attr, k, [:static, v]] }], body]
      end
    end

    # Javascript wrapper engine.
    # Like TagEngine, but can wrap content in html comment or cdata.
    class JavaScriptEngine < TagEngine
      disable_option_validator!

      set_default_options :tag => :script, :attributes => { :type => 'text/javascript' }

      def on_slaml_embedded(engine, body)
        super(engine, [:html, :js, body])
      end
    end

    # Embeds ruby code
    class RubyEngine < Engine
      def on_slaml_embedded(engine, body)
        [:multi, [:newline], [:code, collect_text(body)]]
      end
    end

    # Embeds plain text
    class PlainEngine < Engine
      disable_option_validator!

      def on_slaml_embedded(engine, body)
        [:multi, [:newline], [:escape, options[:escape_html], [:slaml, :interpolate, collect_text(body)]], collect_newlines(body)]
      end
    end

    # Embeds plain text but preserves whitespace
    class PreserveEngine < Engine
      disable_option_validator!

      def on_slaml_embedded(engine, body)
        [:multi, [:newline], call(body)]
      end

      def on_slaml_interpolate(str)
        [:escape, true, [:slaml, :interpolate, str.strip]]
      end

      def on_newline
        [:multi, [:static, '&#x000A;'], [:newline]]
      end
    end

    # Embeds output inside cdata
    class CDATAEngine < Engine
      disable_option_validator!

      def on_slaml_embedded(engine, body)
        [:multi, [:newline], [:static, '<![CDATA['], [:newline],
            [:static, collect_text(body)], [:newline],
            [:static, ']]>'], [:newline], collect_newlines(body)]
      end
    end

    # These engines are executed at compile time, embedded ruby is interpolated
    register :markdown,     InterpolateTiltEngine
    register :textile,      InterpolateTiltEngine
    register :rdoc,         InterpolateTiltEngine
    register :creole,       InterpolateTiltEngine
    register :wiki,         InterpolateTiltEngine
    register :mediawiki,    InterpolateTiltEngine

    # These engines are executed at compile time
    register :coffee,       JavaScriptEngine,                                                           :engine => StaticTiltEngine
    register :coffeescript, JavaScriptEngine,                                                           :engine => StaticTiltEngine
    register :less,         TagEngine, :tag => :style,  :attributes => { :type => 'text/css' },         :engine => StaticTiltEngine
    register :styl,         TagEngine, :tag => :style,  :attributes => { :type => 'text/css' },         :engine => StaticTiltEngine
    register :sass,         TagEngine, :pretty, :tag => :style, :attributes => { :type => 'text/css' }, :engine => SassEngine
    register :scss,         TagEngine, :pretty, :tag => :style, :attributes => { :type => 'text/css' }, :engine => SassEngine

    # These engines are precompiled, code is embedded
    register :erb,          ERBEngine
    register :nokogiri,     PrecompiledTiltEngine
    register :builder,      PrecompiledTiltEngine

    # Embedded javascript/css
    register :javascript,   JavaScriptEngine
    register :css,          TagEngine, :tag => :style,  :attributes => { :type => 'text/css' }

    # Embedded ruby code
    register :ruby,         RubyEngine

    # Plain text
    register :plain,        PlainEngine, :escape_html => false
    register :escaped,      PlainEngine, :escape_html => true
    register :preserve,     PreserveEngine

    # CDATA
    register :cdata,        CDATAEngine
  end
end
