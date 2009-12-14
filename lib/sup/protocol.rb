# encoding: utf-8
require 'socket'
require 'stringio'
require 'bert'

module Redwood
module Protocol

class Connection
  def initialize io
    @io = io
  end

  def self.connect uri
    case uri.scheme
    when 'unix' then new UNIXSocket.new(uri.path)
    when 'tcp' then new TCPSocket.new(uri.host, uri.port)
    else fail "unknown URI scheme #{uri.scheme}"
    end
  end

  def read
    len = @io.read(4).unpack('N')[0]
    BERT.decode @io.read(len)
  end

  def write *o
    bert = BERT.encode o
    bert.force_encoding Encoding::ASCII_8BIT
    len_s = [bert.bytesize].pack('N')
    @io.write(len_s + bert)
  end

  def query querystr, offset, limit, raw
    results = []
    write :query, :query => querystr, :offset => offset, :limit => limit, :raw => raw
    while ((x = read) && x[0] != :done)
      fail "expected message, got #{x[0].inspect}" unless x[0] == :message
      if block_given?
        yield x[1]
      else
        results << x[1]
      end
    end
    block_given? ? nil : results
  end

  def count querystr
    write :count, :query => querystr
    x = read
    x[1][:count]
  end

  def add raw, labels
    write :add, :raw => raw, :labels => labels
    read
  end

  def label querystr, remove, add
    write :label, :query => querystr, :remove => remove, :add => add
    read
  end

  def stream querystr, raw
    send :stream,
          :query => querystr,
          :raw => raw
    while (x = read)
      fail "expected message, got #{x[0].inspect}" unless x[0] == :message
      yield x[1]
    end
  end

  def close
    @io.close unless @io.closed?
  end
end

end
end
