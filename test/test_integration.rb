#!/usr/bin/ruby
# encoding: utf-8

require 'test/unit'
require 'sup'
require 'sup/util'
require 'messages'
require 'tmpdir'
require 'fileutils'
require 'uri'
require 'rbconfig'

RUBY = "#{Config::CONFIG['bindir']}/#{Config::CONFIG['ruby_install_name']}"
EXEC_PATH="./bin"
LIB_PATHS=%w(./lib ./libxapian-1.9)

def debug *o
  puts *o if $VERBOSE
end

class TestIntegration < Test::Unit::TestCase
  def setup
    @path = Dir.mktmpdir
    @tcp_uri = URI.parse 'tcp://localhost:24765'
    @unix_uri = URI.parse "unix:/tmp/sup-sock-#{Process.pid}-#{Time.now.to_i}"
    ENV['SUP_SERVER_BASE'] = @path + '/server'
    ENV['SUP_BASE'] = @path + '/client'
  end

  def teardown
    FileUtils.rm_r @path if passed?
    puts "not cleaning up #{@path}" unless passed?
  end

  def nicely_kill pid, timeout=10
    begin
      Process.kill :TERM, pid rescue Errno::ESRCH
      Timeout.timeout(timeout) { Process.waitpid2 pid }
    rescue Timeout::Error
      puts "#{pid} did not exit in time"
      Process.kill :KILL, pid rescue Errno::ESRCH
      rpid, status = Process.waitpid2 pid
    end[1]
  end

  def run_sup prog, *args
    ruby_args = LIB_PATHS.map { |x| "-I#{x}" }
    ruby_args += [EXEC_PATH + '/' + prog]
    ruby_args += args
    debug "running #{prog} #{args * ' '}"
    IO.popen([RUBY, *ruby_args], 'r+') do |io|
      waited = false
      begin
        if block_given?
          yield io
        else
          io.close_write
          debug "#{prog} reading"
          io.each_line { |l| debug "#{prog}: #{l}" }
          debug "#{prog} finished reading"
        end
      rescue
        debug "#{prog}: #{$!.inspect}"
        raise
      ensure
        debug "#{prog}: killing"
        status = nicely_kill io.pid
        debug "#{prog}: killed"
        fail "#{prog}: unexpected exit code #{status.exitstatus}" unless status.success?
      end
    end
  end

  def with_server
    run_sup "sup-server", '-l', @tcp_uri.to_s, @unix_uri.to_s do |io|
      ENV['SUP_SERVER_BASE'] = nil
      wait_for_server  
      yield io
    end
  end

  def wait_for_server
    sleep 2
  end

  def with_cmd *args, &b
    run_sup 'sup-cmd', '--uri', @tcp_uri.to_s, *args, &b
  end

  def test_basic
    with_server do |srv_io|
      with_cmd('count', 'type:mail') { |io| assert_equal 0, io.read.to_i }
      with_cmd('add', '--mbox') { |io| io.write NormalMessages.mbox; io.close_write; io.read }
      with_cmd('count', 'type:mail') { |io| assert_equal NormalMessages.msgs.size, io.read.to_i }
    end
  end

  def test_sync
    mbox_fn = "#{@path}/mbox"
    mbox_uri = 'mbox:' + mbox_fn
    maildir_fn = "#{@path}/maildir"
    maildir_uri = 'maildir:' + maildir_fn

    File.open(mbox_fn, 'w') { |io| io.write NormalMessages.mbox }
    MoreMessages.make_maildir maildir_fn

    with_server do |srv_io|
      with_cmd('count', 'type:mail') { |io| assert_equal 0, io.read.to_i }
      run_sup("sup-add", mbox_uri)
      run_sup("sup-add", maildir_uri)
      run_sup("sup-sync",'-av', '--uri', @tcp_uri.to_s, mbox_uri)
      with_cmd('count', 'type:mail') { |io| assert_equal NormalMessages.msgs.size, io.read.to_i }
      run_sup("sup-sync",'-av', '--uri', @tcp_uri.to_s, maildir_uri)
      with_cmd('count', 'type:mail') { |io| assert_equal MoreMessages.msgs.size + NormalMessages.msgs.size, io.read.to_i }
    end
  end
end
