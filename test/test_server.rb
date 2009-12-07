#!/usr/bin/ruby

require 'test/unit'
require 'sup'
require 'sup/storage'
require 'sup/server'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'messages'

class TestServer < Test::Unit::TestCase
  def setup
    @path = Dir.mktmpdir
    ENV['SUP_BASE'] = @path
    @store = Redwood::Storage.new File.join(@path, 'db')
    @index = Redwood::XapianIndex.new @path
    @index.load_index
    @server = Redwood::Server.new @index, @store
  end

  def teardown
    @store.close if @store
    FileUtils.rm_r @path if passed?
    puts "not cleaning up #{@path}" unless passed?
  end

  def add_messages w, msgs=NormalMessages.msgs, labels=[]
    msgs.each do |msg|
      w.write :add, :raw => msg, :labels => labels
      w.serve!
      expect w.read, :done
    end
  end

  def test_add
    with_wire do |w|
      add_messages w
    end
  end

  def test_add_with_labels
    with_wire do |w|
      w.write :count, :query => 'label:foo'
      w.serve!
      expect w.read, :count, :count => 0

      add_messages w, NormalMessages.msgs, [:foo]

      w.write :count, :query => 'label:foo'
      w.serve!
      expect w.read, :count, :count => NormalMessages.msgs.size
    end
  end

  def test_count
    with_wire do |w|
      w.write :count, :query => 'CountTestTerm'
      w.serve!
      expect w.read, :count, :count => 0

      add_messages w

      w.write :count, :query => 'CountTestTerm'
      w.serve!
      expect w.read, :count, :count => 1
   end
  end

  def test_query
    with_wire do |w|
      add_messages w
      w.write :query, :query => 'QueryTestTerm'
      w.serve!
      expect w.read, :message
      expect w.read, :message
      expect w.read, :done
    end
  end

  def test_query_ordering
    with_wire do |w|
      add_messages w
      w.write :query, :query => 'QueryOrderingTestTerm'
      w.serve!
      msgs = []
      while (x = w.read)
        type, args, = x
        break if type == :done
        expect x, :message
        msgs << args[:message]
      end

      assert_operator msgs.size, :>, 1
      dates = msgs.map { |m| m[:date] }
      dates.inject { |b,v| assert_operator b, :>=, v; v }
    end
  end

  def test_label
    with_wire do |w|
      add_messages w
      w.write :count, :query => 'label:test'
      w.serve!
      expect w.read, :count, :count => 0
      w.write :label, :query => 'QueryTestTerm', :add => [:test]
      w.serve!
      expect w.read, :done
      w.write :count, :query => 'label:test'
      w.serve!
      expect w.read, :count, :count => 2
    end
  end

  def test_stream
    with_wires(2) do |w1, w2|
      resps = []
      w1.write :stream, :query => 'type:mail'
      t1 = ::Thread.new { w1.serve! }
      t2 = ::Thread.new do
        while (x = w1.read)
          expect x, :message
          resps << x
        end
      end
      add_messages w2
      sleep 3
      w1.close
      w2.close
      t1.kill
      t1.join
      t2.kill
      t2.join
      assert_equal NormalMessages.msgs.size, resps.size
    end
  end

  def with_wire
    with_wires(1) { |w| yield w }
  end

  def with_wires n
    wires = []
    srv_wires = []
    n.times do
      w, srv_w = Redwood::Wire.pair
      c = @server.client srv_w
      w.send(:define_singleton_method, :serve) { c.serve }
      w.send(:define_singleton_method, :serve!) { serve || fail('serve failed') }
      wires << w
      srv_wires << srv_w
    end
    yield *wires
    wires.each { |w| w.close }
    srv_wires.each { |srv_w| srv_w.close }
  end

  def expect resp, type, args={}
    assert_equal type, resp[0]
    args.each do |k,v|
      assert_equal v, resp[1][k]
    end
  end
end
