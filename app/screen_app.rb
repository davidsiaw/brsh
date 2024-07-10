require "opal"
require 'jslib'

require 'native'

require 'screen'
require 'main_screen_display_driver'

puts "jhaha"


class State
  def initialize
    @prev = 0
    @mainscreen = Screen.new('mainscreen', 480, 272, dnd: true)
    @mainscreen.delegate = self
    @mainscreen.display_driver = MainScreenDisplayDriver.new

    @subscreen = Screen.new('subscreen', 480, 120, dnd: false)

    # stuf = HtmlDiv.new(id: 'stuf')
    # HtmlBody.instance.add(stuf)

  end

  def update
    # draw the current frame
    @mainscreen.refresh
    @subscreen.refresh

    # do processing for the next frame

    #stuf = HtmlDiv.new(id: 'stuf')

    now = Time.now.to_f
    prev = @prev

    v = now - prev

    #stuf.js_element.innerText = v
    @prev = now
  end

  def program_loop
    $$.requestAnimationFrame do
      update
      program_loop
    end
  end

end

State.new.program_loop