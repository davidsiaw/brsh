require "js"
require "singleton"
require "native"

class ByteArray
  attr_reader :native_array

  def initialize(*args)
    @native_array = JS.new(`Uint8ClampedArray`, *args)
  end

  def [](pos)
    a = @native_array
    `a[pos]`
  end

  def []=(pos, val)
    a = @native_array
    `a[pos] = val`
  end

  def length
    @native_array.JS[:length]
  end

  def blit(ctx, x, y, w, h)
    arr = @native_array
    imgdata = `new ImageData(arr, w, h, {colorSpace: "srgb"})`
    ctx.putImageData(imgdata, x, y)
  end
end

class Class
  def delegate_props(*property_list, to:)
    property_list.each do |propname|
      define_method propname do
        send(to).send(propname)
      end

      define_method :"#{propname}=" do |value|
        send(to).send(:"#{propname}=", value)
      end
    end
  end
end

module HtmlElement
  attr_reader :js_element

  def initialize(id: nil)
    if id.nil?
      @js_element = $$.document.createElement(tag)
    else
      @js_element = $$.document.getElementById(id)
      if @js_element.nil?
        puts "not found"
        @js_element = $$.document.createElement(tag)
      end
      @js_element.setAttribute('id', id)
    end
  end

  def method_missing(name, *args)
    if name.to_s.end_with?("=")
      @js_element.setAttribute(name.to_s[0..-2], args[0])
    else
      @js_element.getAttribute(name)
    end
  end

  def add(thing)
    @js_element.appendChild(thing.js_element)
  end
end

class HtmlBody
  include HtmlElement
  include Singleton

  def initialize
    @js_element = $$.document.body
  end

  delegate_props :background, :color, to: :style

  def style
    $$.document.body.style
  end
end

class HtmlDiv
  include HtmlElement
  def tag
    'div'
  end
end

class HtmlCanvas
  include HtmlElement
  def tag
    'canvas'
  end

  def context2d
    @js_element.getContext("2d");
  end
end
