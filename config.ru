# config.ru
require 'opal-sprockets'
require 'sinatra'

opal = Opal::Sprockets::Server.new {|s|
  s.append_path 'app'
  s.main = 'application'
  s.debug = ENV['RACK_ENV'] != 'production'
}

map '/assets' do
  run opal.sprockets
end

get '/' do
  File.read('screen.html').sub('{{ internals }}', 
    Opal::Sprockets.javascript_include_tag('table_app', debug: opal.debug, sprockets: opal.sprockets, prefix: 'assets/' )
  )
end

get '/screen' do
  File.read('screen.html').sub('{{ internals }}', 
    Opal::Sprockets.javascript_include_tag('screen_app', debug: opal.debug, sprockets: opal.sprockets, prefix: 'assets/' )
  )
end

get '/xterm' do
  File.read('screen.html').sub('{{ internals }}', 
    Opal::Sprockets.javascript_include_tag('xterm_app', debug: opal.debug, sprockets: opal.sprockets, prefix: 'assets/' )
  )
end

run Sinatra::Application
