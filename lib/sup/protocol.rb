require 'socket'
require 'stringio'
require 'bert'

module Redwood

class Wire
  DEFAULT_TCP_PORT = 2734

  def initialize s
    @s = s
  end

  def self.tcp hostname, port=DEFAULT_TCP_PORT
    s = TCPSocket.new(hostname, port)
    new s
  end

  def self.pair
    s1, s2 = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
    s1.binmode
    s2.binmode
    w1 = new s1
    w2 = new s2
    [w1, w2]
  end

  def write *objs
    bert = BERT.encode objs
    bert.force_encoding Encoding::ASCII_8BIT
    @s.write([bert.length].pack("N") + bert)
  end

  def read
    return unless lenheader = @s.read(4)
    len = lenheader.unpack('N')[0]
    return unless bert = @s.read(len)
    BERT.decode bert
  end

  def close
    @s.close unless @s.closed?
  end
end

end
