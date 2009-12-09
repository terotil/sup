# encoding: utf-8
require 'fileutils'

module Redwood::Server

class IndexLock
  DELAY = 5 # seconds

  class LockError < StandardError
    def initialize h
      @h = h
    end

    def method_missing m; @h[m.to_s] end
  end

  def initialize dir
    @dir = dir
    @lockfile = Lockfile.new path, :retries => 0, :max_age => nil
  end

  def path; File.join @dir, "lock" end

  def lock
    debug "locking #{path}..."
    begin
      @lockfile.lock
    rescue Lockfile::MaxTriesLockError
      raise LockError, @lockfile.lockinfo_on_disk
    end
  end

  def unlock
    if @lockfile.locked?
      debug "unlocking #{path}..."
      @lockfile.unlock
    end
  end

  def lock_interactively stream=$stderr
    begin
      lock
    rescue LockError => e
      stream.puts <<EOS
Error: the index is locked by another process! User '#{e.user}' on
host '#{e.host}' is running #{e.pname} with pid #{e.pid}.
The process was alive as of at least #{e.mtime.to_nice_distance_s} ago.

EOS
      stream.print "Should I ask that process to kill itself (y/n)? "
      stream.flush

      success = if $stdin.gets =~ /^\s*y(es)?\s*$/i
        stream.puts "Ok, trying to kill process..."

        begin
          Process.kill "TERM", e.pid.to_i
          sleep DELAY
        rescue Errno::ESRCH # no such process
          stream.puts "Hm, I couldn't kill it."
        end

        stream.puts "Let's try that again."
        begin
          lock
        rescue LockError => e
          stream.puts "I couldn't lock the index. The lockfile might just be stale."
          stream.print "Should I just remove it and continue? (y/n) "
          stream.flush

          if $stdin.gets =~ /^\s*y(es)?\s*$/i
            FileUtils.rm e.path

            stream.puts "Let's try that one more time."
            begin
              lock
              true
            rescue LockError => e
            end
          end
        end
      end

      stream.puts "Sorry, couldn't unlock the index." unless success
      success
    end
  end

  def start_lock_updater
    @lock_updater = Actor.spawn do
      die = false
      while not die
        Actor.receive do |f|
          f.after(30) { @lockfile.touch_yourself }
          f.when(:die) { die = true }
        end
      end
    end
  end

  def stop_lock_updater
    @lock_updater << :die if @lock_updater
    @lock_updater = nil
  end
end

end
