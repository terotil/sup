#!/usr/bin/ruby

require 'test/unit'
require 'sup'
require 'sup/storage'
require 'sup/server'
require 'stringio'
require 'tmpdir'
require 'fileutils'

class TestServer < Test::Unit::TestCase
  MSGS = [
<<EOM
Date: Fri, 4 Dec 2009 21:57:00 -0800
From: Fake Sender <fake_sender@example.invalid>
To: Fake Receiver <fake_receiver@localhost>
Subject: Re: Test message subject
Message-ID: <20071209194819.GA25972@example.invalid>
References: <E1J1Rvb-0006k2-CE@localhost.localdomain>
In-Reply-To: <E1J1Rvb-0006k2-CE@localhost.localdomain>

Test message!
CountTestTerm
EOM
  ]

  def setup
    @path = Dir.mktmpdir
    ENV['SUP_BASE'] = @path
    @store = Redwood::Storage.new File.join(@path, 'db')
    @index = Redwood::XapianIndex.new @path
    @index.load_index
    @server = Redwood::Server.new @index, @store
    @cleanup = true
  end

  def teardown
    @store.close if @store
    FileUtils.rm_r @path if @cleanup
  end

  def add_messages w, msgs=MSGS
    msgs.each do |msg|
      w.write :add, :raw => msg
      assert w.serve
      assert_equal :done, w.read.first
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
      assert w.serve
      type, args, = w.read
      assert_equal :count, type
      assert_equal 0, args[:count]

      add_messages w

      w.write :count, :query => 'CountTestTerm'
      assert w.serve
      type, args, = w.read
      assert_equal :count, type
      assert_equal 1, args[:count]
   end
  end

  def with_wire
    w, srv_w = Redwood::Wire.pair
    c = @server.client srv_w
    w.send(:define_singleton_method, :serve) { c.serve }
    yield w
    w.close
    srv_w.close
  end
end
