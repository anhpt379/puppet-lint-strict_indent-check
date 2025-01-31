# Public: Check the manifest tokens for correct indent levels and
# record a warning for each instance found.

PuppetLint.new_check(:'strict_indent') do
  def get_heredoc_indent(heredoc)
    if heredoc.value.end_with?("\n")
      indent = 0
    else
      indent = heredoc.value.lines.last.length
    end
    return indent
  end

  def match(tokens)
    opening_token = {
      :RBRACE => :LBRACE,
      :RBRACK => :LBRACK,
      :RPAREN => :LPAREN,
      :HEREDOC => :HEREDOC_OPEN,
      :HEREDOC_POST => :HEREDOC_PRE,
    }
    open = {
      :LBRACE => [],
      :LBRACK => [],
      :LPAREN => [],
      :HEREDOC_OPEN => [],
      :HEREDOC_PRE => [],
    }

    matches = {}

    tokens.each do |token|
      if [:LBRACE, :LBRACK, :LPAREN, :HEREDOC_OPEN, :HEREDOC_PRE].include?(token.type)
        open[token.type] << token
      elsif [:RBRACE, :RBRACK, :RPAREN, :HEREDOC, :HEREDOC_POST].include?(token.type)
        match = open[opening_token[token.type]].pop
        if not match.nil?
          matches[token] = match
          matches[match] = token
        end
      end
    end

    matches
  end

  def check
    chars_per_indent = PuppetLint.configuration.chars_per_indent || 2
    indent = 0
    colon_indent = nil

    matches = match(tokens)

    tokens.select { |token|
      token.type == :NEWLINE
    }.reject { |token|
      # ignore newline at end of code
      token.next_token.nil?
    }.each do |token|
      temp_indent = 0

      # indent for open groups in the previous line
      open_groups = 0
      prev_token = token.prev_token
      while not prev_token.nil? and prev_token.type != :NEWLINE
        if [:HEREDOC_OPEN].include?(prev_token.type)
          temp_indent += 1
        end
        if [:LBRACE, :LBRACK, :LPAREN].include?(prev_token.type)
          if matches[prev_token].nil? or matches[prev_token].line > prev_token.line
            # left braces not matched in the same line increase indent
            open_groups += 1
          end
        end
        prev_token = prev_token.prev_token
      end
      indent += open_groups

      # reset prev_token to last non-whitespace token on previous line
      prev_token = token.prev_token
      while not prev_token.nil? and (prev_token.type == :WHITESPACE or prev_token.type == :COMMENT)
        prev_token = prev_token.prev_token
      end

      # get type if available
      prev_type = prev_token.nil? ? nil : prev_token.type

      # handle change in indent based on last token
      case prev_type
      when :COLON
        if open_groups == 0
          if colon_indent.nil?
            # only indent for a colon when you haven't indented yet
            colon_indent = prev_token.line
            indent += 1
          else
            # you probably missed a semicolon two lines ago
          end
        end
      when :SEMIC
        if not colon_indent.nil?
          # only unindent for a semicolon when we've indented for a colon
          colon_indent = nil
          indent -= 1
        end
      when :EQUALS, :FARROW
        temp_indent += 1
      end

      # unindent for closing brackets in the current line
      next_token = token.next_token
      while not next_token.nil? and next_token.type != :NEWLINE
        if [:RBRACE, :RBRACK, :RPAREN].include?(next_token.type)
          if not matches[next_token].nil? and matches[next_token].line < next_token.line
            # right braces matched in a previous line decrease indent
            indent -= 1
          end
          if next_token.type == :RBRACE and not colon_indent.nil?
            if not matches[next_token].nil? and matches[next_token].line < colon_indent
              # unindent at the end of resources if needed
              indent -= 1
              colon_indent = nil
            end
          end
        end
        next_token = next_token.next_token
      end

      # obviously we have a problem
      if indent < 0
        notify :error, {
          :message => 'Error calculating indent',
          :line    => token.next_token.line,
          :column  => token.next_token.column,
          :token   => token.next_token,
        }
        # stop parsing indent
        break
      end

      # get actual indent
      actual = 0
      if token.next_token.type == :INDENT
        actual = token.next_token.value.length
      elsif token.next_token.type == :RBRACE
        actual = token.next_token.value[/^ */].size
      elsif !token.next_token.nil? and token.next_token.type == :HEREDOC_PRE
        actual = token.next_token.value[/^ */].size
      elsif !token.prev_token.nil? and token.prev_token.type == :HEREDOC
        actual = get_heredoc_indent(token.prev_token)
      elsif !token.next_token.nil? and token.next_token.type == :HEREDOC
        actual = get_heredoc_indent(token.next_token)
      elsif !next_token.nil? and !token.prev_token.nil? and token.prev_token.type == :HEREDOC_OPEN
        actual = get_heredoc_indent(next_token.prev_token)
      else
        actual = 0
      end

      # expected indent
      expected = (indent + temp_indent) * chars_per_indent

      # oh no! incorrect indent!
      if actual != expected
        # no one cares if blank lines are indented correctly
        if not [:NEWLINE].include?(token.next_token.type)
          notify :warning, {
            :message => "indent should be #{expected} chars and is #{actual}",
            :line    => token.next_token.line,
            :column  => token.next_token.column,
            :token   => token.next_token,
            :indent  => expected,
          }
        end
      end
    end
  end

  def fix(problem)
    if not problem[:indent]
      return
    end
    char_for_indent = ' '
    if [:INDENT,:WHITESPACE].include?(problem[:token].type)
      problem[:token].value = char_for_indent * problem[:indent]
    else
      if problem[:token].type == :HEREDOC
        current_indent = get_heredoc_indent(problem[:token])
        problem[:token].raw.gsub!(/^#{char_for_indent * current_indent}/, char_for_indent * problem[:indent])
      elsif problem[:token].type == :HEREDOC_PRE
        heredoc_pre = problem[:token]

        heredoc_mids = []
        heredoc_post = nil
        token = heredoc_pre
        while token.next_token
          if token.type == :HEREDOC_MID
            heredoc_mids.push(token)
          elsif token.type == :HEREDOC_POST
            heredoc_post = token
            break
          end
          token = token.next_token
        end

        current_indent = get_heredoc_indent(heredoc_post)

        heredoc_pre.value.gsub!(/^#{char_for_indent * current_indent}/, char_for_indent * problem[:indent])
        if heredoc_pre.value.end_with?("\n")
          heredoc_pre.value += char_for_indent * problem[:indent]
        end
        heredoc_mids.each { |heredoc_mid|
          heredoc_mid.value.gsub!(/\n#{char_for_indent * current_indent}/, "\n" + char_for_indent * problem[:indent])
        }
        heredoc_post.raw.gsub!(/\n#{char_for_indent * current_indent}/, "\n" + char_for_indent * problem[:indent])
      else
        tokens.insert(
          tokens.find_index(problem[:token]),
          PuppetLint::Lexer::Token.new(:INDENT, char_for_indent * problem[:indent], problem[:line], problem[:column])
        )
      end
    end
  end
end
