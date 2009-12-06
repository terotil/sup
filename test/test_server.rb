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

  def add_messages w, msgs=NormalMessages.msgs
    msgs.each do |msg|
      w.write :add, :raw => msg
      w.serve!
      expect w.read, :done
    end
  end

  def test_add
    with_wire do |w|
      add_messages w
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

  def with_wire
    w, srv_w = Redwood::Wire.pair
    c = @server.client srv_w
    w.send(:define_singleton_method, :serve) { c.serve }
    w.send(:define_singleton_method, :serve!) { serve || fail('serve failed') }
    yield w
    w.close
    srv_w.close
  end

  def expect resp, type, args={}
    assert_equal type, resp[0]
    args.each do |k,v|
      assert_equal v, resp[1][k]
    end
  end
end
