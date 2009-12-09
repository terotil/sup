require 'thread'
require 'zlib'

module Redwood
module Server

class Storage
  LEVEL = Zlib::BEST_SPEED
  FOOTER_SIZE = 8
  FOOTER_FMT = 'NN'

  def initialize fn
    exists = File.exists? fn

    @io = if exists
      File.new(fn, 'r+b')
    else
      File.new(fn, 'w+b')
    end

    @length = @io.stat.size
    @lock = Mutex.new
  end

  def put data
    puts "storing #{data.inspect}" if $VERBOSE
    fail 'closed' if @io.closed?
    zdata = Zlib::Deflate.deflate data, LEVEL
    zsize = zdata.bytesize
    @lock.synchronize do
      offset = @io.pos = @length
      @io.write zdata
      offset += zsize
      @io.write [mkhash(offset), zsize].pack(FOOTER_FMT)
      @length = offset + FOOTER_SIZE
      offset
    end
  end

  def get offset
    fail 'closed' if @io.closed?
    zdata = @lock.synchronize do
      @io.pos = offset
      magic, zsize, = @io.read(FOOTER_SIZE).unpack(FOOTER_FMT)
      fail "bad magic" unless magic == mkhash(offset)
      @io.pos = offset - zsize
      @io.read zsize
    end
    Zlib::Inflate.inflate zdata
  end

  def close
    @io.close
  end

  def mkhash x
    (x * 2654435761) & 0xFFFFFFFF
  end
end

end
end
