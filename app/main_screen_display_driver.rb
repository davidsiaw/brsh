class MainScreenDisplayDriver
  def draw(screen)
    ctx = screen.ctx

    ctx.fillStyle = "blue"
    ctx.fillRect(0, 0, screen.width, screen.height)
    ctx.fillStyle = "black"
    ctx.font = "48px serif";

    ba = ByteArray.new(400)

    @col ||= 0
    @col = (@col + 1) % 256

    80.times do |x|
      ba[x] = @col
    end

    ba.blit(ctx, 50, 100, 10, 10)

    case screen.mode
    when :init
      ctx.fillText("init", 10, 50);
    when :draginside
      ctx.fillText("draginside", 10, 50);
    when :loading
      ctx.fillText("loading", 10, 50);
    when :running
      ctx.fillText("running", 10, 50);
    else
      ctx.fillText("error", 10, 50);
    end
  end
end
