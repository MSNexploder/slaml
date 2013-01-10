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
        line = @line.strip
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

      @tab = ' ' * options[:tabsize]
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
      line[/\A[ \t]*/].gsub("\t", @tab).size
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
        @stacks.last << [:html, :doctype, parse_doctype($'.strip)]
      when /\A\/\[\s*(.*?)\s*\]\s*\Z/
        # HTML conditional comment
        block = [:multi]
        @stacks.last << [:html, :condcomment, $1, block]
        @stacks << block
      when /\A\/( ?)/
        # HTML comment
        @stacks.last << [:html, :comment, [:static, $']]
      when /\A-#/
        # Haml comment
        parse_comment_block
      when /\A\\=/
        # Plain text escaping
        @stacks.last << [:static, $']
      else
        syntax_error! 'Unknown line indicator'
      end
      @stacks.last << [:newline]
    end

    def parse_doctype(str)
      str = str.downcase

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
