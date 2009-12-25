#!/usr/bin/ruby
# encoding: utf-8

require 'test/unit'
require 'sup/server'
require 'sup/queryparser'
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
      write w, 'add', 'raw' => msg, 'labels' => labels
      expect read(w), 'done'
    end
  end

  def q text
    Redwood::QueryParser.parse text
  end

  def test_add
    with_wire do |w|
      add_messages w
    end
  end

  def test_add_with_labels
    with_wire do |w|
      write w, 'count', 'query' => q('label:foo')
      expect read(w), 'count', 'count' => 0

      add_messages w, NormalMessages.msgs, ['foo']

      write w, 'count', 'query' => q('label:foo')
      expect read(w), 'count', 'count' => NormalMessages.msgs.size
    end
  end

  def test_count
    with_wire do |w|
      write w, 'count', 'query' => q('CountTestTerm')
      expect read(w), 'count', 'count' => 0

      add_messages w

      write w, 'count', 'query' => q('CountTestTerm')
      expect read(w), 'count', 'count' => 1
   end
  end

  def test_query
    with_wire do |w|
      add_messages w
      write w, 'query', 'query' => q('QueryTestTerm')
      expect read(w), 'message'
      expect read(w), 'message'
      expect read(w), 'done'
    end
  end

  def test_query_ordering
    with_wire do |w|
      add_messages w
      write w, 'query', 'query' => q('QueryOrderingTestTerm')
      summaries = []
      while (x = read(w))
        type, args, = x
        break if type == 'done'
        expect x, 'message'
        summaries << args['summary']
      end

      assert_operator summaries.size, :>, 1
      dates = summaries.map { |m| m['date'] }
      dates.inject { |b,v| assert_operator b, :>=, v; v }
    end
  end

  def test_label
    with_wire do |w|
      add_messages w
      write w, 'count', 'query' => q('label:test')
      expect read(w), 'count', 'count' => 0
      write w, 'label', 'query' => q('QueryTestTerm'), 'add' => ['test']
      expect read(w), 'done'
      write w, 'count', 'query' => q('label:test')
      expect read(w), 'count', 'count' => 2
    end
  end

  def test_stream
    with_wires(2) do |w1, w2|
      a = []
      write w1, 'stream', 'query' => q('type:mail')
      add_messages w2
      Actorized.msgloop do |f|
        f.when(T[:msg, w1]) { |_,_,m| a << m }
        f.after(1) { throw :die }
      end
      assert_equal NormalMessages.msgs.size, a.size
    end
  end

  def test_stream_cancel
    msgs = NormalMessages.msgs
    with_wires(2) do |w1, w2|
      a = []
      write w1, 'stream', 'query' => q('type:mail'), 'tag' => 42

      add_messages w2, [msgs[0]]
      Actorized.msgloop do |f|
        f.when(T[:msg, w1]) { |_,_,m| a << m }
        f.after(1) { throw :die }
      end
      assert_equal 1, a.size

      write w2, 'cancel', 'tag' => 42

      add_messages w2, [msgs[1]]
      Actorized.msgloop do |f|
        f.when(T[:msg, w1]) { |_,_,m| a << m }
        f.after(1) { throw :die }
      end
      assert_equal 1, a.size
    end
  end

  def test_multiple_accept
    with_wires(2) do |w1,w2|
      add_messages w1
      write w2, 'count', 'query' => q('type:mail')
      expect read(w2), 'count', 'count' => NormalMessages.msgs.size
    end
  end

  def with_wire
    with_wires(1) { |w| yield w }
  end

  def with_wires n
    wires = []
    n.times do
      s = Redwood::Protocol.unix(@socket_path)
      wires << Redwood::Protocol::ConnectionActor.spawn_link(s, Actor.current)
    end
    yield *wires
    wires.each { |w| w << :die }
  end

  def read w
    debug "reading from #{w.inspect}"
    ret = nil
    Actor.receive do |f|
      f.when(T[:msg, w]) do |_,_,m|
        ret = m
      end
    end
    debug "finished reading from #{w.inspect}"
    ret
  end

  def write w, *m
    debug "writing to #{w.inspect}"
    w << T[:msg, Actor.current, m]
  end

  def expect resp, type, args={}
    assert_equal type.to_s, resp[0]
    args.each do |k,v|
      assert_equal v, resp[1][k.to_s]
    end
  end
end
