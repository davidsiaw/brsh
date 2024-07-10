require "opal"
require 'jslib'

require 'native'

require 'singleton'

class XTermDeps
  include Singleton

  def start(object, methodname)
    object.send(methodname)
  end

  def load(object, methodname)
    return object.send(methodname) if @loaded

    `
      var link = document.createElement('link');
      link.onload = function () {
          //do stuff with the script
      };
      link.rel = "stylesheet"
      link.href = "https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.min.css";

      var script = document.createElement('script');
      script.onload = function () {
        Opal.XTermDeps.$instance().$start(object, methodname)

      };
      script.src = "https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js";

      document.head.appendChild(link); 
      document.head.appendChild(script); 
    `
    @loaded = true
  end
end

class XTerm
  attr_reader :term
  def initialize(id: 'terminal')
    @div = HtmlDiv.new(id: id)
    @term = JS.new(`Terminal`)

    div = @div
    @term.JS.open(`div.js_element.native`);

    @cursor = {x:0,y:0}

    internal_initialize!
  end

  def js_element
    @div.js_element
  end

  def internal_initialize!
    term = @term
    cursor = @cursor
    @term.JS.onCursorMove do |e|
      cursor[:x] = `term.buffer.active.cursorX`
      cursor[:y] = `term.buffer.active.cursorY`
      #Object.puts(cursor)
    end
  end

  def cursor_x
    @cursor[:x]
  end

  def cursor_y
    @cursor[:y]
  end

  def cursor_x=(val)
    move_cursor_to(val, @cursor[:y])
  end

  def cursor_y=(val)
    move_cursor_to(@cursor[:x], val)
  end

  def move_cursor_to(x,y)
    @term.JS.write("\u001b[#{y+1};#{x+1}H")
  end

  def write(str)
    @term.JS.write(str.to_s)
  end
end

XTermDeps.instance.load(self, :start)

class Key
  attr_reader :code,:char,:key,:ctrl,:alt,:shift
  def initialize(code:,char:,key:,ctrl:,alt:,shift:)
    @code = code
    @char = char
    @key = key
    @ctrl = ctrl
    @alt = alt
    @shift = shift
  end
end

class ForegroundInterface
  attr_accessor :target

  def initialize(target)
    @target = target
  end

  def write(str)
    target.term.write(str)
  end

  def show_cursor
    target.term.write("\x1b[?25h")
  end

  def hide_cursor
    target.term.write("\x1b[?25l")
  end

  def set_cursor_x(x)
    target.term.cursor_x = x
  end
end

class Foreground
  attr_reader :term
  def initialize(term)
    @term = term
    @currapi = ForegroundInterface.new(self)

    jibun = self
    @term.term.JS.onKey do |k,e|
      thekey = Key.new(
        code: `k.key`,
        char: `k.domEvent.key`,
        key: `k.domEvent.code`,
        ctrl: `k.domEvent.ctrlKey`,
        alt: `k.domEvent.altKey`,
        shift: `k.domEvent.shiftKey`
      )
      jibun.key(thekey)
    end
  end

  def key(thekey)
    if program.respond_to?(:on_key)
      program.on_key(thekey)
    end
  end

  def program
    @program
  end

  def program=(val)
    if program.respond_to?(:on_end)
      program.on_end
    end

    @program = val
    @currapi.target = nil

    if program.respond_to?(:on_start)
      @currapi = ForegroundInterface.new(self)
      program.on_start(@currapi)
    end

  end
end

class BasicProgram
  # used to receive the interface to talk to the terminal
  def on_start(api)
    @api = api
  end

  # used to understand that it has lost foreground
  def on_end
  end

  # while foreground, keypresses call this method
  def on_key(thekey)
  end
end

class Echoer < BasicProgram
  def on_key(thekey)
    @api.write(thekey.char)
  end
end

class Shell < BasicProgram
  def initialize
    @history = []
    @prompt = "input: "
  end

  def on_start(api)
    @api = api
    write_prompt!
  end

  def write_prompt!
    @api.write(@prompt)
    @currline = ""
    @curpos = @currline.length
  end

  def ischar?(chrcode)
    (chrcode >= '0'.ord && chrcode <= '9'.ord) ||
    (chrcode >= 'a'.ord && chrcode <= 'z'.ord) ||
    (chrcode >= 'A'.ord && chrcode <= 'Z'.ord)
  end

  def key_position_command(thekey)
    if thekey.alt && thekey.key == "ArrowLeft"
      if @curpos > 0
        x = @curpos - 1
        loop do
          break if x == 0
          charbefore = @currline[x - 1].ord
          nonchar = ischar?(charbefore)
          break unless nonchar
          x -= 1
        end
        @curpos = x
      end

    elsif thekey.alt && thekey.key == "ArrowRight"
      if @curpos < @currline.length
        x = @curpos + 1
        loop do
          break if x == @currline.length
          charbefore = @currline[x - 1].ord
          nonchar = ischar?(charbefore)
          break unless nonchar
          x += 1
        end
        @curpos = x
      end

    elsif thekey.key == "ArrowLeft"
      @curpos = @curpos - 1
      @curpos = 0 if @curpos < 0

    elsif thekey.key == "ArrowRight"
      @curpos = @curpos + 1
      @curpos = @currline.length if @curpos > @currline.length

    elsif thekey.key == "Backspace"
      if @curpos > 0
        @currline = @currline[0...@curpos-1] + @currline[@curpos..-1]
        @curpos = @curpos - 1
        refresh_line!
      end

    elsif thekey.key == "Delete"
      if @curpos < @currline.length
        @currline = @currline[0...@curpos] + @currline[@curpos+1..-1]
        refresh_line!
      end

    elsif thekey.key == "End"
      @curpos = @currline.length

    elsif thekey.key == "Home"
      @curpos = 0

    else
      return false
    end

    @api.set_cursor_x(@prompt.length + @curpos)
    true
  end

  def key_special_command(thekey)
    if thekey.key == "ArrowUp"
    elsif thekey.key == "ArrowDown"
    else
      return false
    end

    true
  end

  def refresh_line!
    @api.hide_cursor
    @api.set_cursor_x(@prompt.length)
    @api.write(@currline + " ")
    @api.set_cursor_x(@prompt.length + @curpos + 1)
    @api.show_cursor
  end

  def on_key(thekey)
    if thekey.key == 'Enter'
      @api.write("\r\n")
      return run!
    end

    if key_position_command(thekey)
      return
    end

    if key_special_command(thekey)
      return
    end

    if thekey.alt || thekey.ctrl
      return
    end

    if thekey.char.length > 1
      puts "bigchar: '#{thekey.char}'"
      return
    end

    if @curpos == @currline.length
      # end of line
      @currline += thekey.char
      @api.write(thekey.char)
    else
      # mid or beginning of line
      line = @currline
      @currline = line[0...@curpos] + thekey.char + line[@curpos..-1]
      refresh_line!
    end
    @curpos += 1

  end

  def run!
    @history << @currline
    # parse shit and do stuff
    puts @currline

    @currline = ""

    write_prompt!
  end
end

def start
  xterm = XTerm.new
  HtmlBody.instance.add(xterm)
  fg = Foreground.new(xterm)

  fg.program = Shell.new


  # xterm.write("a\n")

  # puts(xterm.cursor_x)

  # xterm.write("click here: \x1b]8;;#\x07text\x1b]8;;\x07")
  # puts(xterm.cursor_x)

  # xterm.move_cursor_to(10,10)

  # xterm.term.JS.onKey do |k,e|


  #   Object.puts key

  #   #{}`console.log(k,e)`
  # end


  # div = HtmlDiv.new(id: 'terminal')
  # HtmlBody.instance.add(div)

  # term = JS.new(`Terminal`)

  # term.JS.onCursorMove do |e|
  #   `console.log(term.buffer.active.cursorX)`

  # end

  # term.JS.open(`div.js_element.native`);
  # term.JS.write("\u001b[5C")


  # puts term.JS[:buffer].JS[:active].JS[:cursorX]
  # term.JS.write("\u001b[2B")
end
