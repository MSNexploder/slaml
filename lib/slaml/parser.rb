module Slaml
  # Parses Haml code and transforms it to a Temple expression
  # @api private
  class Parser < Temple::Parser
    define_options :file,
                   :tabsize => 4,
                   :escape_html => false,
                   :format => 'html5',
                   :encoding => 'utf-8'

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
      str = remove_bom(set_encoding(str))

      result = [:multi]
      reset(str.split(/\r?\n/), [result])

      parse_line while next_line

      reset
      result
    end

    protected

    WORD_RE = ''.respond_to?(:encoding) ? '\p{Word}' : '\w'

    # Set string encoding if option is set
    def set_encoding(s)
      if options[:encoding] && s.respond_to?(:encoding)
        old_enc = s.encoding
        s = s.dup if s.frozen?
        s.force_encoding(options[:encoding])
        # Fall back to old encoding if new encoding is invalid
        s.force_encoding(old_enc) unless s.valid_encoding?
      end
      s
    end

    # Remove unicode byte order mark from string
    def remove_bom(s)
      if s.respond_to?(:encoding)
        if s.encoding.name =~ /^UTF-(8|16|32)(BE|LE)?/
          s.gsub(Regexp.new("\\A\uFEFF".encode(s.encoding.name)), '')
        else
          s
        end
      else
        s.gsub(/\A\xEF\xBB\xBF/, '')
      end
    end

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
        @stacks.last << [:html, :doctype, parse_doctype($')]
      when /\A\/\[\s*(.*?)\s*\]\s*\Z/
        # HTML conditional comment
        block = [:multi]
        @stacks.last << [:html, :condcomment, $1, block]
        @stacks << block
      when /\A\//
        # HTML comment
        comment = " #{$'.strip} "
        @stacks.last << [:html, :comment, [:static, comment]]
      when /\A%([#{WORD_RE}:]+)/
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
      when /\A=/
        @line = $'
        @stacks.last << [:escape, options[:escape_html], [:dynamic, parse_broken_line]]
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
      when /\A(.*)/
        @stacks.last << [:static, $1]
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
      @stacks.last << tag

      case @line
      when /\A\s*=(=?)/
        # Handle output code
        @line = $'
        content = [:multi, [:escape, $1 != '=', [:dynamic, parse_broken_line]]]
        tag << content
        @stacks << content
      when /\A\s*\Z/
        # Empty content
        content = [:multi]
        tag << content
        @stacks << content
      when /\A\s*\/\s*/
        # Closed tag. Do nothing
        @line = $'
        syntax_error!('Unexpected text after closed tag') unless @line.empty?
      when /\A( ?)(.*)\Z/
        # Text content
        content = [:multi]
        content << [:static, $2]
        tag << content
        @stacks << content
      end
    end

    def parse_attributes
      attributes = [:html, :attrs]

      # Find any shortcut attributes
      attr_shortcut = {
        '.' => 'class',
        '#' => 'id'
      }
      while @line =~ /\A([\.#])(#{WORD_RE}+)/
        attributes << [:html, :attr, attr_shortcut[$1], [:static, $2]]
        @line = $'
      end

      attributes
    end

    def parse_doctype(str)
      str = str.strip.downcase

      case options[:format].to_s
      when 'html5'
        # When the :format option is set to :html5, !!! is always <!DOCTYPE html>.
        'html'
      when 'html4'
        if %w(strict frameset).include? str
          str
        else
          'transitional'
        end
      when 'xhtml'
        # TODO missing !!! RDFa
        if %w(strict frameset 5 1.1 basic mobile).include? str
          str
        else
          'transitional'
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

    def parse_text_block(first_line = nil, text_indent = nil)
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
          break if indent <= @indents.last

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

          result << [:newline] << [:slaml, :interpolate, (text_indent ? "\n" : '') + (' ' * offset) + @line]

          # The indentation of first line of the text block
          # determines the text base indentation.
          text_indent ||= indent
        end
      end
      result
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
