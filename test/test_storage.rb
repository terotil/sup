#!/usr/bin/ruby
# encoding: utf-8

require 'test/unit'
require 'sup/storage'
require 'stringio'
require 'tmpdir'
require 'fileutils'

class TestStorage < Test::Unit::TestCase
  def setup
    @path = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_r @path
  end

  def with_store fn='db', &b
    store = Redwood::Server::Storage.new File.join(@path, fn)
    ret = b.yield store
    store.close
    ret
  end

  def test_simple
    data = [
      'foo',
      'bar---',
      "\000\n\b\abop",
      'zap+',
    ]
    data.each { |d| d.force_encoding Encoding::ASCII_8BIT }

    offsets = []

    with_store do |store|
      data.each do |d|
        assert d.valid_encoding?
        offsets << store.put(d)
        offsets.zip(data).each do |o2,d2|
          d3 = store.get o2
          assert d3.valid_encoding?
          assert_equal d2, d3
        end
      end

      data.zip(offsets).shuffle.each do |d,o|
        d2 = store.get o
        assert_equal d, d2
      end
    end
  end

  def test_reopen
    d = 'x'
    o = with_store { |store| store.put d }
    x = with_store { |store| store.get o }
    assert_equal d, x
  end
end
