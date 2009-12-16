# encoding: utf-8
require 'rubygems'
require 'rack'
require 'sup'
require 'sup/protocol'
require 'sup/util'
require 'sup/message'
require 'socket'
require 'uri'
require 'haml'

SERVER_URI = Redwood::DEFAULT_URI

class Redwood::Web
  def initialize uri
    @uri = URI.parse uri
  end

  def call env
    req = Rack::Request.new env
    resp = Rack::Response.new
    sym = req.path[1..-1].to_sym
    if respond_to? sym
      c = Redwood::Protocol::Connection.connect @uri
      begin
        send sym, c, req, resp
      ensure
        c.close
      end
    else
      resp.status = 404
    end
    resp.finish
  end

  def render name, locals
    path = File.dirname(__FILE__) + "/#{name}.haml"
    haml = File.read path
    Haml::Engine.new(haml).render(Object.new, locals)
  end

  def query c, req, resp
    s = req[:s]
    summaries = c.query(s, 0, 100, false).map { |x| x['summary'] }
    resp.write(render :query, summaries: summaries)
  end

  def view c, req, resp
    msgid = req[:message_id]
    s = "msgid:#{msgid}"
    result = c.query(s, 0, 1, true).first
    fail "nil result" unless result
    m = Redwood::Message.parse result['raw'], :labels => result['summary']['labels']
    resp.write(render :view, message: m)
  end
end

if __FILE__ == $0
  class Rack::Response
    include Enumerable
  end
  web = Redwood::Web.new SERVER_URI
  env = Rack::MockRequest.env_for(ARGV.first || 'http://localhost:8765/query?s=foo')
  resp = web.call env
  puts resp[2].body
end
