# encoding: utf-8
require 'socket'
require 'stringio'
require 'bert'

module Redwood
module Protocol
	def self.read io
		len = io.read(4).unpack('N')[0]
		BERT.decode io.read(len)
	end

	def self.write io, *o
		bert = BERT.encode o
		bert.force_encoding Encoding::ASCII_8BIT
		len_s = [bert.bytesize].pack('N')
		io.write(len_s + bert)
	end

	def self.connect_normal uri
		case uri.scheme
		when 'unix' then UNIXSocket.new uri.path
		when 'tcp' then TCPSocket.new uri.host, uri.port
    else fail "unknown URI scheme #{uri.scheme}"
		end
	end
end
end
