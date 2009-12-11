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
	P = Redwood::Protocol

	def initialize uri
		@uri = URI.parse uri
	end

	def call env
		req = Rack::Request.new env
		resp = Rack::Response.new
		sym = req.path[1..-1].to_sym
		if respond_to? sym
			c = Redwood::Protocol::connect_normal @uri
			begin
				send sym, c, req, resp
			ensure
				c.close unless c.closed?
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
		summaries = []
		P.write c, :query, query: s, offset: 0, limit: 100
  	while ((x = P.read(c)) && x.first != :done)
			summaries << x[1][:message]
		end
		resp.write(render :query, summaries: summaries)
	end

	def view c, req, resp
		msgid = req[:message_id]
		s = "msgid:#{msgid}"
		summary = nil
		raw = nil
		P.write c, :query, query: s, offset: 0, limit: 1, raw: true
  	while ((x = P.read(c)) && x.first != :done)
			summary = x[1][:message]
			raw = x[1][:raw]
		end
		m = Redwood::Message.parse raw, :labels => summary[:labels]
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
