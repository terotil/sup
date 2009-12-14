# encoding: utf-8
require 'socket'
require 'stringio'
require 'bert'

module Redwood
module Protocol

## BERT 1.1.0 does not handle strings with multibyte characters
## correctly. Convert them all to binary.
## TODO abstract out traversal
## TODO make decoding less wrong
## TODO fix bert
def self.bert_binify o
  case o
  when Hash
    h = {}
    o.each { |k,v| h[bert_binify(k)] = bert_binify(v) }
    h
  when Array
    o.map { |x| bert_binify x }
  when String
    o = o.dup
    o.force_encoding Encoding::BINARY
  else
    o
  end
end

def self.bert_unbinify o
  case o
  when Hash
    h = {}
    o.each { |k,v| h[bert_binify(k)] = bert_binify(v) }
    h
  when Array
    o.map { |x| bert_binify x }
  when String
    o = o.dup
    o.force_encoding Encoding::UTF_8
    begin
      o.check
    rescue
      o.force_encoding Encoding::ASCII_8BIT
    end
  else
    o
  end
end

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
    Redwood::Protocol.bert_unbinify(BERT.decode(@io.read(len)))
  end

  def write *o
    bert = BERT.encode(Redwood::Protocol.bert_binify(o))
    bert.force_encoding Encoding::ASCII_8BIT
    len_s = [bert.bytesize].pack('N')
    @io.write(len_s + bert)
  end

  def query q, offset, limit, raw
    Redwood::QueryParser.validate q
    results = []
    write :query, :query => q, :offset => offset, :limit => limit, :raw => raw
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

  def count q
    Redwood::QueryParser.validate q
    write :count, :query => q
    x = read
    x[1][:count]
  end

  def add raw, labels
    write :add, :raw => raw, :labels => labels
    read
  end

  def label q, remove, add
    Redwood::QueryParser.validate q
    write :label, :query => q, :remove => remove, :add => add
    read
  end

  def stream q, raw
    Redwood::QueryParser.validate q
    send :stream,
          :query => q,
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
