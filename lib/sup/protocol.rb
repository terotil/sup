# encoding: utf-8
require 'socket'
require 'stringio'
require 'yajl'

module Redwood
module Protocol

VERSION = 1
ENCODINGS = %w(marshal json)

def self.version_string encodings=ENCODINGS, extensions=[]
  fail if encodings.empty?
  "Redwood #{VERSION} #{encodings * ','} #{extensions.empty? ? :none : (extensions * ',')}"
end

def self.parse_version l
  l =~ /^Redwood\s+(\d+)\s+([\w,]+)\s+([\w,]+)$/ or fail "unexpected banner #{l.inspect}"
  version = $1.to_i
  encodings = $2.split ','
  extensions = $3.split ','
  extensions = [] if extensions == ['none']
  fail unless version == Redwood::Protocol::VERSION
  fail if encodings.empty?
  [encodings, extensions]
end

def self.choose_encoding encodings
  (Redwood::Protocol::ENCODINGS & encodings).first
end

def self.create_filter encoding
  case encoding
  when 'json' then JSONFilter.new
  when 'marshal' then MarshalFilter.new
  else fail "unknown encoding #{encoding.inspect}"
  end
end

class JSONFilter
  def initialize
    @parser = Yajl::Parser.new :check_utf8 => false
  end

  def decode chunk
    parsed = []
    @parser.on_parse_complete = lambda { |o| parsed << o }
    @parser << chunk
    parsed
  end

  def encode *os
    os.inject('') { |s, o| s << Yajl::Encoder.encode(o) }
  end
end

class MarshalFilter
  def initialize
    @buf = ''
    @state = :prefix
    @size = 0
  end

  def decode chunk
    received = []
    @buf << chunk

    begin
      if @state == :prefix
        break unless @buf.size >= 4
        prefix = @buf.slice!(0...4)
        @size = prefix.unpack('N')[0]
        @state = :data
      end

      fail unless @state == :data
      break if @buf.size < @size
      received << Marshal.load(@buf.slice!(0...@size))
      @state = :prefix
    end until @buf.empty?

    received
  end

  def encode o
    data = Marshal.dump o
    [data.size].pack('N') + data
  end
end

class Connection
  def initialize io
    @io = io
    @parsed = []
    @filter = nil
    negotiate
  end

  def self.connect uri
    case uri.scheme
    when 'unix' then new UNIXSocket.new(uri.path)
    when 'tcp' then new TCPSocket.new(uri.host, uri.port)
    else fail "unknown URI scheme #{uri.scheme}"
    end
  end

  def negotiate
    l = @io.readline
    encodings, extensions = Redwood::Protocol.parse_version l
    encoding = Redwood::Protocol.choose_encoding encodings
    @filter = Redwood::Protocol.create_filter encoding
    @io.write(Redwood::Protocol.version_string([encoding], extensions) + "\n")
  end

  def fix_encoding x
    case x
    when String
      x = x.dup
      x.force_encoding Encoding::UTF_8
      x
    when Hash
      Hash[x.map { |k,v| [fix_encoding(k), fix_encoding(v)] }]
    when Array
      x.map { |v| fix_encoding(v) }
    else
      x
    end
  end

  def read
    while @parsed.empty?
      chunk = @io.readpartial 1024
      @parsed += @filter.decode chunk
    end
    type, args = @parsed.shift
    fail unless type.is_a? String and args.is_a? Hash
    fix_encoding [type, args]
  end

  def write *o
    @io.write @filter.encode(o)
  end

  def query q, offset, limit, raw
    Redwood::QueryParser.validate q
    results = []
    write 'query', 'query' => q, 'offset' => offset, 'limit' => limit, 'raw' => raw
    while ((x = read) && x[0] != 'done')
      fail "expected message, got #{x[0].inspect}" unless x[0] == 'message'
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
    write 'count', 'query' => q
    x = read
    x[1]['count']
  end

  def add raw, labels
    write 'add', 'raw' => raw, 'labels' => labels
    read
  end

  def label q, remove, add
    Redwood::QueryParser.validate q
    write 'label', 'query' => q, 'remove' => remove, 'add' => add
    read
  end

  def stream q, raw
    Redwood::QueryParser.validate q
    send 'stream',
          'query' => q,
          'raw' => raw
    while (x = read)
      fail "expected message, got #{x[0].inspect}" unless x[0] == 'message'
      yield x[1]
    end
  end

  def query_full q, offset, limit
    query(q,offset,limit,true).map do |result|
      raw = result['raw']
      raw.force_encoding Encoding::ASCII_8BIT
      Redwood::Message.parse raw
    end
  end

  def close
    @io.close unless @io.closed?
  end
end

end
end
