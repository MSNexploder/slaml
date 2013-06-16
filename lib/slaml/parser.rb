module Slaml
  # Parses Haml code and transforms it to a Temple expression
  # @api private
  class Parser < Temple::Parser
    define_options :file,
                   :tabsize => 4,
                   :escape_html => false,
                   :format => :html5

    class SyntaxError < StandardError
      attr_reader :error, :file, :line, :lineno, :column

      def initialize(error, file, line, lineno, column)
        @error = error
        @file = file || '(__TEMPLATE__)'
        @line = line.to_s
        @lineno = lineno
        @column = column
      end

      def to_s
        line = @line.lstrip
        column = @column + line.size - @line.size
        %{#{error}
  #{file}, Line #{lineno}, Column #{@column}
    #{line}
    #{' ' * column}^
}
      end
    end

    def initialize(opts = {})
      super

      tabsize = options[:tabsize]
      if tabsize > 1
        @tab_re = /\G((?: {#{tabsize}})*) {0,#{tabsize-1}}\t/
        @tab = '\1' + ' ' * tabsize
      else
        @tab_re = "\t"
        @tab = ' '
      end
    end

    # Compile string to Temple expression
    #
    # @param [String] str Haml code
    # @return [Array] Temple expression representing the code]]
    def call(str)
      result = [:multi]
      reset(str.split(/\r?\n/), [result])

      parse_line while next_line

      reset
      result
    end

    protected

    WORD_RE = ''.respond_to?(:encoding) ? '\p{Word}' : '\w'
    ATTR_NAME = "\\A\\s*(#{WORD_RE}(?:#{WORD_RE}|:|-)*)"
    ATTR_VARIABLE = "(@?(?:#{WORD_RE})+)"
    RUBY_LITERAL = "((?::?#{WORD_RE}+)|(?:'(?:#{WORD_RE}|:)+')|(?:\"(?:#{WORD_RE}|:)+\"))"
    RUBY_CALL = "(@?(?:#{WORD_RE}|[\\.\\[\\]:()])+)"
    BOOLEAN_HTML_ATTR_RE = /\A\s*#{ATTR_NAME}(?:=(true|false))?/
    QUOTED_HTML_ATTR_RE = /\A\s*#{ATTR_NAME}=("|')/
    CODE_HTML_ATTR_RE = /\A\s*#{ATTR_NAME}=#{ATTR_VARIABLE}/
    STATIC_RUBY_ATTR_RE = /\A\s*#{RUBY_LITERAL}\s*(?:=>|:)\s*("|')/
    CODE_RUBY_ATTR_RE = /\A\s*#{RUBY_LITERAL}\s*(?:=>|:)\s*#{RUBY_CALL}\s*[,]?/

    def reset(lines = nil, stacks = nil)
      # Since you can indent however you like in Haml, we need to keep a list
      # of how deeply indented you are. For instance, in a template like this:
      #
      #   doctype       # 0 spaces
      #   html          # 0 spaces
      #    head         # 1 space
      #       title     # 4 spaces
      #
      # indents will then contain [0, 1, 4] (when it's processing the last line.)
      #
      # We uses this information to figure out how many steps we must "jump"
      # out when we see an de-indented line.
      @indents = [0]

      # Whenever we want to output something, we'll *always* output it to the
      # last stack in this array. So when there's a line that expects
      # indentation, we simply push a new stack onto this array. When it
      # processes the next line, the content will then be outputted into that
      # stack.
      @stacks = stacks

      @lineno = 0
      @lines = lines
      @line = @orig_line = nil
    end

    def next_line
      if @lines.empty?
        @orig_line = @line = nil
      else
        @orig_line = @lines.shift
        @lineno += 1
        @line = @orig_line.dup
      end
    end

    def get_indent(line)
      # Figure out the indentation. Kinda ugly/slow way to support tabs,
      # but remember that this is only done at parsing time.
      line[/\A[ \t]*/].gsub(@tab_re, @tab).size
    end

    def parse_line
      if @line =~ /\A\s*\Z/
        @stacks.last << [:newline]
        return
      end

      indent = get_indent(@line)

      # Remove the indentation
      @line.lstrip!

      # If there's more stacks than indents, it means that the previous
      # line is expecting this line to be indented.
      expecting_indentation = @stacks.size > @indents.size

      if indent > @indents.last
        # This line was actually indented, so we'll have to check if it was
        # supposed to be indented or not.
        syntax_error!('Unexpected indentation') unless expecting_indentation

        @indents << indent
      else
        # This line was *not* indented more than the line before,
        # so we'll just forget about the stack that the previous line pushed.
        @stacks.pop if expecting_indentation

        # This line was deindented.
        # Now we're have to go through the all the indents and figure out
        # how many levels we've deindented.
        while indent < @indents.last
          @indents.pop
          @stacks.pop
        end

        # This line's indentation happens lie "between" two other line's
        # indentation:
        #
        #   hello
        #       world
        #     this      # <- This should not be possible!
        syntax_error!('Malformed indentation') if indent != @indents.last
      end

      parse_line_indicators
    end

    def parse_line_indicators
      case @line
      when /\A!!!\s*/
        # Found doctype declaration
        @stacks.last << parse_doctype($')
      when /\A\/\[\s*(.*?)\s*\]\s*\Z/
        # HTML conditional comment
        block = [:multi]
        @stacks.last << [:html, :condcomment, $1, block]
        @stacks << block
      when /\A\//
        # HTML comment
        comment = parse_text_block($'.strip)
        @stacks.last << [:html, :comment, [:multi, [:static, ' '], comment, [:static, ' ']]]
      when /\A%([#{WORD_RE}:-]+)/
        # HTML element
        @line = $'
        parse_tag($1)
      when /\A[\.#]/
        # id / class shortcut
        parse_tag('div')
      when /\A-#/
        # Haml comment
        parse_comment_block
      when /\A&=/
        # HTML escaping
        @line = $'
        @stacks.last << [:escape, true, [:dynamic, parse_broken_line]]
      when /\A!=/
        # HTML unescaping
        @line = $'
        @stacks.last << [:escape, false, [:dynamic, parse_broken_line]]
      when /\A=(=?)/
        # Found an output block.
        # We expect the line to be broken or the next line to be indented.
        @line =~ /\A=(=?)/
        @line = $'
        block = [:multi]
        @stacks.last << [:slaml, :output, $1 != '=', parse_broken_line, block]
        @stacks << block
      when /\A-/
        # Ruby code block
        # We expect the line to be broken or the next line to be indented.
        @line.slice!(0)
        block = [:multi]
        @stacks.last << [:slaml, :control, parse_broken_line, block]
        @stacks << block
      when /\A:(\w+)\s*\Z/
        # Embedded template detected. It is treated as block.
        @stacks.last << [:slaml, :embedded, $1, parse_text_block]
      when /\A\\=/
        # Plain text escaping
        @stacks.last << [:static, $']
      when /\A(\s*)/
        # Plain text
        @stacks.last << [:slaml, :text, parse_text_block($', @indents.last + $1.size, true)]
      else
        syntax_error! 'Unknown line indicator'
      end
      @stacks.last << [:newline]
    end

    def parse_broken_line
      broken_line = @line.strip
      while broken_line =~ /[,]s*\Z/
        expect_next_line
        broken_line << "\n" << @line
      end
      broken_line
    end

    def parse_tag(tag)
      tag = [:html, :tag, tag, parse_attributes]
      inner, outer = parse_whitespace_tag

      if outer
        @stacks.last << [:slaml, :whitespace, 'outer', tag]
      else
        @stacks.last << tag
      end

      if inner
        tag << inner_tag = [:slaml, :whitespace, 'inner']
        tag = inner_tag
      end

      case @line
      when /\A\s*=(=?)/
        # Handle output code
        @line = $'
        block = [:multi]
        tag << [:slaml, :output, $1 != '=', parse_broken_line, block]
        @stacks << block
      when /\A\s*\Z/
        # Empty content
        content = [:multi]
        tag << content
        @stacks << content
      when /\A\s*\/\s*/
        # Closed tag. Do nothing
        @line = $'
        syntax_error!('Unexpected text after closed tag') unless @line.empty?
      when /\A(\s*)(.*)\Z/
        # Text content
        tag << [:slaml, :text, parse_text_block($2, @orig_line.size - @line.size + $1.size)]
      end
    end

    def parse_attributes
      attributes = [:html, :attrs]

      # Find any shortcut attributes
      attr_shortcut = {
        '.' => 'class',
        '#' => 'id'
      }
      while @line =~ /\A([\.#])((?:#{WORD_RE}|-)+)/
        if $1 == '#'
          # special 'shortcut' case  - gets concatenated not overwritten
          attributes << [:slaml, :shortattr, attr_shortcut[$1], [:static, $2]]
        else
          attributes << [:html, :attr, attr_shortcut[$1], [:static, $2]]
        end
        @line = $'
      end

      while true
        case @line
        # HTML Syntax
        when /\A\s*\(/
          @line = $'
          attributes.concat(parse_html_attributes)
        # Ruby 1.8 / 1.9 Syntax
        when /\A\s*\{/
          @line = $'
          attributes.concat(parse_ruby_attributes)
        else
          break
        end
      end

      attributes
    end

    def parse_doctype(str)
      type, encoding = str.split
      type = type ? type.strip.downcase : type

      case options[:format].to_s
      when 'html5'
        if type == 'xml'
          [:static, '']
        else
          # When the :format option is set to :html5, !!! is always <!DOCTYPE html>.
          [:html, :doctype, 'html']
        end
      when 'html4'
        if type == 'xml'
          [:static, '']
        elsif %w(strict frameset).include? type
          [:html, :doctype, type]
        else
          [:html, :doctype, 'transitional']
        end
      when 'xhtml'
        if type == 'rdfa'
          [:static, '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML+RDFa 1.0//EN" "http://www.w3.org/MarkUp/DTD/xhtml-rdfa-1.dtd">']
        elsif type == 'xml'
          encoding = encoding || 'utf-8'
          [:static, "<?xml version='1.0' encoding='#{encoding.strip}' ?>"]
        elsif %w(strict frameset 5 1.1 basic mobile).include? type
          [:html, :doctype, type]
        else
          [:html, :doctype, 'transitional']
        end
      else
        syntax_error! 'Unknown format'
      end
    end

    def parse_comment_block
      while !@lines.empty? && (@lines.first =~ /\A\s*\Z/ || get_indent(@lines.first) > @indents.last)
        next_line
        @stacks.last << [:newline]
      end
    end

    def parse_text_block(first_line = nil, text_indent = nil, in_text = false)
      result = [:multi]
      if !first_line || first_line.empty?
        text_indent = nil
      else
        result << [:slaml, :interpolate, first_line]
      end

      empty_lines = 0
      until @lines.empty?
        if @lines.first =~ /\A\s*\Z/
          next_line
          result << [:newline]
          empty_lines += 1 if text_indent
        else
          indent = get_indent(@lines.first)
          if in_text
            break if indent < @indents.last
          else
            break if indent <= @indents.last
          end

          if empty_lines > 0
            result << [:slaml, :interpolate, "\n" * empty_lines]
            empty_lines = 0
          end

          next_line
          @line.lstrip!

          # The text block lines must be at least indented
          # as deep as the first line.
          offset = text_indent ? indent - text_indent : 0
          if offset < 0
            syntax_error!("Text line not indented deep enough.\n" +
                          "The first text line defines the necessary text indentation.")
          end

          result << [:slaml, :interpolate, (text_indent ? "\n" : '') + (' ' * offset) + @line]

          # The indentation of first line of the text block
          # determines the text base indentation.
          text_indent ||= indent
        end
      end
      result
    end

    def parse_whitespace_tag
      inner = false
      outer = false
      while true
        case @line
        when /\A</
          # remove inner whitespace
          @line = $'
          inner = true
        when /\A>/
          # remove outer whitespace
          @line = $'
          outer = true
        else
          break
        end
      end

      [inner, outer]
    end

    def parse_html_attributes
      attributes = []
      end_re = /\A\s*\)/
      while true
        case @line
        when QUOTED_HTML_ATTR_RE
          # Value is quoted (static)
          @line = $'
          attributes << [:html, :attr, $1,
                         [:escape, options[:escape_html], [:slaml, :interpolate, parse_quoted_attribute($2)]]]
        when CODE_HTML_ATTR_RE
          # Value is dynamic
          @line = $'
          attributes << [:html, :attr, $1, [:slaml, :attrvalue, false, $2]]
        when BOOLEAN_HTML_ATTR_RE
          # Boolean attribute
          @line = $'
          attributes << [:html, :attr, $1, [:slaml, :attrvalue, false, $2 || true]]
        else
          case @line
          when end_re
            @line = $'
            break
          else
            # Found something where an attribute should be
            @line.lstrip!
            syntax_error!('Expected attribute') unless @line.empty?

            # Attributes span multiple lines
            @stacks.last << [:newline]
            syntax_error!("Expected closing delimiter )") if @lines.empty?
            next_line
          end
        end
      end
      attributes
    end

    def parse_ruby_attributes
      attributes = []
      end_re = /\A\s*\}/
      while true
        case @line
        when STATIC_RUBY_ATTR_RE
          # Static value
          @line = $'
          name = $1
          delim = $2
          attributes << [:html, :attr, cleanup_attr_name(name),
                         [:escape, options[:escape_html], [:slaml, :interpolate, parse_quoted_attribute(delim)]]]

          @line.match(/\s*[,]?/)
          @line = $'
        when CODE_RUBY_ATTR_RE
          # Value is ruby code
          @line = $'
          name = $1
          value = $2
          attributes << [:html, :attr, cleanup_attr_name(name), [:slaml, :attrvalue, false, value]]
        else
          case @line
          when end_re
            @line = $'
            break
          else
            # Found something where an attribute should be
            @line.lstrip!
            syntax_error!('Expected attribute') unless @line.empty?

            # Attributes span multiple lines
            @stacks.last << [:newline]
            syntax_error!("Expected closing delimiter }") if @lines.empty?
            next_line
          end
        end
      end
      attributes
    end

    def parse_quoted_attribute(quote)
      value, count = '', 0

      until @line.empty? || (count == 0 && @line[0] == quote[0])
        if @line =~ /\A\\\Z/
          value << ' '
          expect_next_line
        else
          if count > 0
            if @line[0] == ?{
              count += 1
            elsif @line[0] == ?}
              count -= 1
            end
          elsif @line =~ /\A#\{/
            value << @line.slice!(0)
            count = 1
          end
          value << @line.slice!(0)
        end
      end

      syntax_error!("Expected closing brace }") if count != 0
      syntax_error!("Expected closing quote #{quote}") if @line[0] != quote[0]
      @line.slice!(0)

      value
    end

    def cleanup_attr_name(name)
      name.sub(/\A:/, '').sub(/\A[\"'](.*)[\"']\Z/, '\1')
    end

    # Helper for raising exceptions
    def syntax_error!(message)
      raise SyntaxError.new(message, options[:file], @orig_line, @lineno,
                            @orig_line && @line ? @orig_line.size - @line.size : 0)
    end

    def expect_next_line
      next_line || syntax_error!('Unexpected end of file')
      @line.strip!
    end
  end
end
