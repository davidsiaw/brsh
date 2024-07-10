class Screen
  attr_reader :canvas, :mode, :ctx, :width, :height
  attr_accessor :delegate
  attr_accessor :display_driver

  def initialize(name, width, height, dnd:)
    @canvas = HtmlCanvas.new(id: name)
    @mode = :init
    @ctx = canvas.context2d
    @width = width
    @height = height
    @name = name
    @dnd = dnd

    canvas.width = width
    canvas.height = height
    canvas.js_element.style.imageRendering = 'pixelated'
    canvas.js_element.style.display = 'block'

    enable_dnd if dnd

    HtmlBody.instance.add(canvas)
  end

  def enable_dnd
    canvas.js_element.addEventListener('dragenter') do |e|
      @mode = :draginside
      puts "dragenter"
      e.JS.preventDefault
    end

    canvas.js_element.addEventListener('dragleave') do |e|
      @mode = :init
      puts "dragleave"
      e.JS.preventDefault
    end

    canvas.js_element.addEventListener('dragover') do |e|
      puts "dragover"
      e.JS.preventDefault
    end

    canvas.js_element.addEventListener('drop') do |e|
      @mode = :loading
      puts "drop"

      filecount = `e.dataTransfer.files.length`
      if filecount == 1
        file = `e.dataTransfer.files[0]`

        reader = JS.new(`FileReader`)

        reader.JS.onload = proc do |re|
          ba = ByteArray.new(`re.target.result`)
          # puts ba.native_array.JS[:length]
          # puts ba[0]
          if delegate&.respond_to?(:cartridge_load)
            delegate.cartridge_load(ba)
          end
        end

        reader.JS.readAsArrayBuffer(file);
      end

      e.JS.preventDefault
    end

    canvas.js_element.addEventListener('dragstart') do |e|
      puts "dragstart"
      e.preventDefault()
    end

    canvas.js_element.addEventListener('dragend') do |e|
      puts "dragend"
      e.preventDefault
    end
  end

  def refresh
    display_driver&.draw(self)
  end
end
