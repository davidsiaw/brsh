require "opal"
require 'jslib'

require 'native'

class HtmlTable
  include HtmlElement
  def tag
    'table'
  end
end

class HtmlTr
  include HtmlElement
  def tag
    'tr'
  end
end

class HtmlTd
  include HtmlElement
  def tag
    'td'
  end
end



class Machine
  attr_accessor :stack, :vars, :mr, :pc, :flags
  def initialize
    @stack = [0] * 8
    @vars = [0] * 16
    @mr = [0] * 4
    @pc = 0
    @flags = {
      zero: 0
    }
  end
end

class Operations
  def aa
  end
end

class Decoder
  def decodeop(byte, machine)

  end

end

puts Operations.new.public_methods(false).inspect

table = HtmlTable.new(id: 'table')
HtmlBody.instance.add(table)

tr = HtmlTr.new()

table.add(tr)

td = HtmlTd.new()
td.js_element[:innerText] = "A"

td.js_element.addEventListener('click') do |e|
  puts 'A'
end

tr.add(td)

td = HtmlTd.new()
td.js_element[:innerText] = "B"

tr.add(td)

tr = HtmlTr.new()

table.add(tr)

td = HtmlTd.new()
td.js_element[:innerText] = "C"

tr.add(td)

td = HtmlTd.new()
td.js_element[:innerText] = "D"

tr.add(td)
