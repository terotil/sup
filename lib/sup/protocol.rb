require 'socket'
require 'bert'

module Redwood

class Protocol
	DEFAULT_PORT = 2734

	def initialize s
		@s = s
	end

	def self.tcp hostname, port=DEFAULT_PORT
		new TCPSocket.new(hostname, port)
	end

	def write *objs
		bert = BERT.encode objs
		@s.write([bert.length].pack("N") + bert)
	end

	def read
		return unless lenheader = @s.read(4)
		len = lenheader.unpack('N')[0]
		return unless bert = @s.read(len)
		BERT.decode bert
	end
end

end
