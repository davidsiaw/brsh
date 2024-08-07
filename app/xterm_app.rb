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

  def clear
    @term.JS.clear
  end

  def show_cursor
    @term.JS.write("\x1b[?25h")
  end

  def hide_cursor
    @term.JS.write("\x1b[?25l")
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
    @api.putstr(thekey.char)
  end
end

class ProcessState
  attr_reader :pid

  def initialize(target, pid)
    @latent_target = target
    @pid = pid
  end

  def disable!
    @latent_target = @target
    @target = nil
  end

  def enable!
    @target = @latent_target
  end

  def clear
    @target&.clear(@pid)
  end

  def putstr(str)
    @target&.write(@pid, str)
  end

  def show_cursor
    @target&.show_cursor(@pid)
  end

  def hide_cursor
    @target&.hide_cursor(@pid)
  end

  def set_cursor_x(x)
    @target&.set_cursor_x(@pid, x)
  end

  def writefd(fd, str)
  end

  def readfd(fd)
  end

  def exit
    @target&.close_process(@pid)
  end

  def exec(args)
    @target&.open_process(@pid, args[0], args[1..-1] || [])
  end
end

class Task < BasicProgram
  def on_start(api)
    @api = api
  end
end

class IdMaker
  def initialize
    @size = 1
    @allocated = {}
    @freelist = [0]
  end

  def alloc_id
    if @freelist.length == 0
      new_numbers = @size
      new_numbers.times do |x|
        @allocated[x + @size] = false
      end
      @size *= 2
    end

    id = @freelist.shift
    @allocated[id] = true
    id
  end

  def free_id(val)
    raise "freelist #{val} unknown" unless @allocated.key?(val)
    raise "freelist #{val} already free" unless @allocated[val] == true

    @allocated[val] = false
    @freelist << val
  end
end

class StreamObject
  def initialize
    @buf = ""
  end

  def write(val)
    @buf += val.to_s
  end

  def read
    result = @buf
    @buf = ""
    return result
  end

end

class ProcessManager
  def initialize
    @foreground = nil
    @execlist = []

    @procidmaker = IdMaker.new
    @processlist = {}

    @streamidmaker = IdMaker.new
    @streamlist = []

    Dispatcher.instance.addlistener("XTERM_EMITTED", "procevent", self, :handle_xterm_event)
  end

  def handle_xterm_event(args)
    case(args[0])
    when "key"
      return if @foreground.nil?
      pid = @foreground

      return unless @processlist.key?(pid)

      @processlist[pid][:program].on_key(args[1])
    end
  end

  def open_process(pid, progname, args)
    program = if progname == "readline"
      Readline.new
    else
      # todo open a process based on a file
      raise "not implemented"
    end

    pid = @procidmaker.alloc_id
    state = ProcessState.new(self, pid)
    program.on_start(state)

    @processlist[pid] = {
      parent: nil,
      state: state,
      program: program,
    }
    return pid
  end

  def close_process(pid)
    return unless @processlist.key?(pid)
    process = @processlist[pid]

    process.on_end

    if @foreground == pid
      @foreground = process[:parent]
    end

    @procidmaker.free_id(pid)
    @processlist.delete(pid)
  end

  def bring_to_fore(pid)
    @processlist[@foreground][:state].disable! unless @foreground.nil?
    @foreground = pid
    @processlist[pid][:state].enable!
  end

  def clear(pid)
    Dispatcher.instance.dispatch("XTERM_LISTENED", ["clear"])
  end

  def write(pid, str)
    Dispatcher.instance.dispatch("XTERM_LISTENED", ["write", str])
  end

  def show_cursor(pid)
    Dispatcher.instance.dispatch("XTERM_LISTENED", ["show_cursor"])
  end

  def hide_cursor(pid)
    Dispatcher.instance.dispatch("XTERM_LISTENED", ["hide_cursor"])
  end

  def set_cursor_x(pid, x)
    Dispatcher.instance.dispatch("XTERM_LISTENED", ["set_cursor_x", x])
  end
end

require 'shellwords'

class Readline < Task
  def initialize
    @prompt = ""
  end

  def on_start(api)
    super

    write_prompt!
  end

  def write_prompt!
    @api.hide_cursor
    @api.putstr(@prompt)
    @currline = ""
    @curpos = @currline.length
    @api.show_cursor
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
    @api.putstr(@currline + " ")
    @api.set_cursor_x(@prompt.length + @curpos + 1)
    @api.show_cursor
  end

  def on_key(thekey)
    if thekey.key == 'Enter'
      @api.putstr("\r\n")
      return run!
    end

    return if key_position_command(thekey)
    return if key_special_command(thekey)

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
      @api.putstr(thekey.char)
    else
      # mid or beginning of line
      line = @currline
      @currline = line[0...@curpos] + thekey.char + line[@curpos..-1]
      refresh_line!
    end
    @curpos += 1
  end

  def run!
    # @history << @currline
    # # parse shit and do stuff

    # if @currline == "clear"
    #   @api.clear
    # end

    # p Shellwords.split(@currline)

    # @api.exec(PwdCommand.new)

    puts @currline


    # @api.sendline(@currline)
    # @currline = ""

    # write_prompt!
  end
end

class PwdCommand < Task
  def on_start(api)
    super

    @api.putstr("pwd\r\n")

    @api.exit
  end
end


class Filesystem
  def initialize
    # initialize and set current dir to root
  end

  def currentdir
    # show current dir
  end

  def moveup
    # go to parent of current dir
  end

  def enterdir
    # change current dir
  end

  def listdir
    # return some strings
  end
end

class Dispatcher
  include Singleton
  def initialize
    @evt_files = {}
  end

  def register_event(event_file)
    raise "name #{event_file.name} already taken" if @evt_files.key?(event_file.name)

    @evt_files[event_file.name] = event_file
    event_file.dispatcher = self
  end

  def deregister_event(event_file)
    @evt_files.delete(event_file.name) if @evt_files.key?(event_file.name)

    event_file.name = nil
    event_file.dispatcher = nil
  end

  def addlistener(event_name, listener_name, target_object, target_method)
    raise "event '#{event_name}' not found " unless @evt_files.key?(event_name)

    @evt_files[event_name].addlistener(listener_name, target_object, target_method)
  end

  def removelistener(event_name, listener_name)
    return unless @evt_files.key?(event_name)

    @evt_files[event_name].removelistener(listener_name)
  end

  def dispatch(event_name, arg_array)
    return unless @evt_files.key?(event_name)

    receivers = @evt_files[event_name].receivers
    receivers.each do |x|
      obj = x[:obj]
      sel = x[:sel]

      # asynchronously call out
      `setTimeout(function(){
        obj.$send(sel, arg_array)
      }, 0)`
    end
  end
end

class ListenerGroup
  attr_accessor :name, :dispatcher

  def initialize(name)
    @name = name
    @listener_array = {}
  end

  def addlistener(listener_name, target_object, target_method)
    @listener_array[listener_name] = {
      obj: target_object,
      sel: target_method
    }
  end

  def removelistener(listener_name)
    return unless @listener_array.key?(listener_name)

    @listener_array.delete(listener_name)
  end

  def dispatch(arg_array)
    return if dispatcher.nil?
    return if name.nil?

    dispatcher.dispatch(name, arg_array)
  end

  def receivers
    @listener_array.values
  end
end

class Listeeerr
  def meow(args)
    k = args[0]
    p k.key
  end
end

class XTermDriver
  def initialize(term, dp)
    @term = term
    @emitter = ListenerGroup.new("XTERM_EMITTED")
    @listener = ListenerGroup.new("XTERM_LISTENED")

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

    @dp = dp
    dp.register_event(@emitter)
    dp.register_event(@listener)

    @listener.addlistener("ownlistener", self, :process_event)
  end

  def key(thekey)
    @emitter.dispatch(["key", thekey])
  end

  def process_event(args)
    case args[0]
    when "clear"
      @term.clear
    when "write"
      @term.write(args[1].to_s)
    when "show_cursor"
      @term.show_cursor
    when "hide_cursor"
      @term.hide_cursor
    when "set_cursor_x"
      @term.cursor_x = args[1].to_i
    end
  end

end

class XTermWriter
  def initialize(term, evtfile)
    @term = term
    @evtfile = evtfile
  end
end


def start
  xterm = XTerm.new
  HtmlBody.instance.add(xterm)

  dp = Dispatcher.instance

  rdr = XTermDriver.new(xterm, dp)


  # lls = Listeeerr.new
  # xterm_emitted_events.addlistener("meow", lls, :meow)

  pm = ProcessManager.new

  pl = pm.open_process(nil, "readline", [])

  pm.bring_to_fore(pl)


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
