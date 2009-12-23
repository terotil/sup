#!/usr/bin/ruby
# encoding: utf-8

require 'test/unit'
require 'sup/protocol'
require 'sup/protocol-actors'

class TestProtocol < Test::Unit::TestCase
  def setup
  end

  def teardown
  end

  def test_actor_decode
    f = Redwood::Protocol::Filter.new
    assert_equal ["foo\n"], f.decode("foo\n[\"t\", {\"x\":1")
    assert_equal [['t', { 'x' => 1 }]], f.decode("}]")
    assert_equal [['t2', { }]], f.decode('["t2",{}]')
  end

  def test_actor_encode
    f = Redwood::Protocol::Filter.new
    assert_equal "foo\n", f.encode("foo")
    assert_equal '["x",{"y":1}]', f.encode(['x',{'y'=>1}])
  end
end
