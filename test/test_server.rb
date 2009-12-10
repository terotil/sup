#!/usr/bin/ruby
# encoding: utf-8

require 'test/unit'
require 'sup/server'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'messages'

class TestServer < Test::Unit::TestCase
  def setup
    @path = Dir.mktmpdir
    @store = Redwood::Server::StorageActor.spawn_link(Redwood::Server::Storage.new File.join(@path, 'storage'))
    @index = Redwood::Server::IndexActor.spawn_link(Redwood::Server::Index.new(File.join(@path, 'index')))
    @server = Redwood::Server::Dispatcher.spawn_link @index, @store
    @socket_path = File.join(@path, 'socket')
    @listener = Redwood::Protocol::UnixListener.listen @server, @socket_path
  end

  def teardown
    @listener << :die if @listener
    @server << :die if @server
    @store << :die if @store
    @index << :die if @index
    FileUtils.rm_r @path if passed?
    puts "not cleaning up #{@path}" unless passed?
  end

  def add_messages w, msgs=NormalMessages.msgs, labels=[]
    msgs.each do |msg|
      w.send :add, :raw => msg, :labels => labels
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
      w.send :count, :query => 'label:foo'
      expect w.read, :count, :count => 0

      add_messages w, NormalMessages.msgs, [:foo]

      w.send :count, :query => 'label:foo'
      expect w.read, :count, :count => NormalMessages.msgs.size
    end
  end

  def test_count
    with_wire do |w|
      w.send :count, :query => 'CountTestTerm'
      expect w.read, :count, :count => 0

      add_messages w

      w.send :count, :query => 'CountTestTerm'
      expect w.read, :count, :count => 1
   end
  end

  def test_query
    with_wire do |w|
      add_messages w
      w.send :query, :query => 'QueryTestTerm'
      expect w.read, :message
      expect w.read, :message
      expect w.read, :done
    end
  end

  def test_query_ordering
    with_wire do |w|
      add_messages w
      w.send :query, :query => 'QueryOrderingTestTerm'
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
      w.send :count, :query => 'label:test'
      expect w.read, :count, :count => 0
      w.send :label, :query => 'QueryTestTerm', :add => [:test]
      expect w.read, :done
      w.send :count, :query => 'label:test'
      expect w.read, :count, :count => 2
    end
  end

  class Reader
    extend Actorize

    def initialize wire, a
      die = false
      wire.controller = Actor.current
      wire.active = true
      while not die
        Actor.receive do |f|
          f.when(T[Case::Any.new(:unix,:tcp)]) { |_,_,m| a << m }
          f.when(:die) { die = true }
        end
      end
    end
  end

  def test_stream
    with_wires(2) do |w1, w2|
      a = []
      w1.send :stream, :query => 'type:mail'
      reader = Reader.spawn w1, a
      add_messages w2
      Actor.sleep 1
      assert_equal NormalMessages.msgs.size, a.size
      reader << :die
    end
  end

  def test_stream_cancel
    msgs = NormalMessages.msgs
    with_wires(2) do |w1, w2|
      a = []
      w1.send :stream, :query => 'type:mail', :tag => 42
      reader = Reader.spawn w1, a

      add_messages w2, [msgs[0]]
      Actor.sleep 1
      assert_equal 1, a.size

      w2.send :cancel, :tag => 42

      add_messages w2, [msgs[1]]
      Actor.sleep 1
      assert_equal 1, a.size

      reader << :die
    end
  end

  def test_multiple_accept
    with_wires(2) do |w1,w2|
      add_messages w1
      w2.send :count, :query => 'type:mail'
      expect w2.read, :count, :count => NormalMessages.msgs.size
    end
  end

  def with_wire
    with_wires(1) { |w| yield w }
  end

  def with_wires n
    wires = []
    n.times do
      wires << Redwood::Protocol.unix(@socket_path)
    end
    yield *wires
    wires.each { |w| w.close }
  end

  def expect resp, type, args={}
    assert_equal type, resp[0]
    args.each do |k,v|
      assert_equal v, resp[1][k]
    end
  end
end
