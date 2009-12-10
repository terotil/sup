#!/usr/bin/ruby
# encoding: utf-8

DEBUG_ENCODING = true

require 'test/unit'
require 'sup/util'
require 'messages'
require 'tmpdir'
require 'fileutils'
require 'uri'

RUBY = "ruby"
EXEC_PATH="./bin"
LIB_PATHS=%w(./lib ./libxapian-1.9)

class TestIntegration < Test::Unit::TestCase
  def setup
    @path = Dir.mktmpdir
    @tcp_uri = URI.parse 'tcp://localhost:24765'
    @unix_uri = URI.parse "unix:/tmp/sup-sock-#{Process.pid}-#{Time.now.to_i}"
  end

  def teardown
    @listener << :die if @listener
    @store.close if @store
    FileUtils.rm_r @path if passed?
    puts "not cleaning up #{@path}" unless passed?
  end

  def run_sup prog, *args
    ruby_args = LIB_PATHS.map { |x| "-I#{x}" }
    ruby_args += [EXEC_PATH + '/' + prog]
    ruby_args += args
    IO.popen([RUBY, *ruby_args], 'r+')
  end

  def with_server
    ENV['SUP_SERVER_BASE'] = @path
    io = run_sup "sup-server", '-l', @tcp_uri.to_s, @unix_uri.to_s
    ENV['SUP_SERVER_BASE'] = nil
    begin
      wait_for_server  
      yield io
    ensure
      Process.kill :KILL, io.pid
    end
  end

  def wait_for_server
    sleep 1
  end

  def with_cmd *args
    io = run_sup 'sup-cmd', '--uri', @tcp_uri.to_s, *args
    begin
      yield io
    ensure
      Process.kill :KILL, io.pid
    end
  end

  def test_basic
    with_server do |srv_io|
      with_cmd('count', 'type:mail') { |io| assert_equal 0, io.read.to_i }
      with_cmd('add', '--mbox') { |io| io.write NormalMessages.mbox; io.close_write; io.read }
      with_cmd('count', 'type:mail') { |io| assert_equal NormalMessages.msgs.size, io.read.to_i }
    end
  end
end
