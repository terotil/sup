# encoding: utf-8
require 'sup/actor'
require 'pp'

class Revactor::TCP::Socket
  def send *o
    write [o]
  end
end

class Revactor::UNIX::Socket
  def send *o
    write [o]
  end
end

module Redwood
module Protocol
  class Filter
    def initialize
      @sent_version = false
      @received_version = false
      @buf = ''
    end

    def decode data
      if not @received_version
        @buf << data
        if i = @buf.index("\n")
          @received_version = true
          l = @buf.slice!(0..i)
          buf = @buf
          @buf = nil
          [l] + normal_decode(buf)
        else
          []
        end
      else
        normal_decode data
      end
    end

    def normal_decode data
      @parser ||= Yajl::Parser.new :check_utf8 => false
      os = []
      @parser.on_parse_complete = lambda do |(type,args)|
        fail unless type.is_a? String and args.is_a? Hash
        os << [type, args]
      end
      @parser << data
      os
    end

    def encode *os
      if not @sent_version
        o = os.shift
        fail unless o.is_a? String
        @sent_version = true
        (o + "\n") + normal_encode(*os)
      else
        normal_encode *os
      end
    end

    def normal_encode *os
      os.inject('') { |s, o| s << Yajl::Encoder.encode(o) }
    end
  end

  FILTERS = [Filter]

  class GenericListener < Actorized
    def run server, l, accept
      l.controller = l.instance_eval { @receiver = Actor.current }
      l.active = true
      main_msgloop do |f|
        l.enable unless l.enabled?
        f.when(accept) do |_, _, sock|
          server << T[:client, sock]
        end
      end
    end
  end

  class TCPListener < GenericListener
    def initialize server, listener
      super server, listener, T[:tcp_connection, listener]
    end

    def self.listener host, port
      Revactor::TCP.listen host, port, :filter => FILTERS
    end

    def self.listen server, host, port
      spawn server, listener(host, port)
    end
  end

  def self.tcp host, port
    Revactor::TCP.connect host, port, :filter => FILTERS
  end

  class UnixListener < GenericListener
    def initialize server, listener, path
      @path = path
      super server, listener, T[:unix_connection, listener]
    end

    def ensure
      FileUtils.rm_f @path
    end

    def self.listener path
      Revactor::UNIX.listen path, :filter => FILTERS
    end

    def self.listen server, path
      spawn server, listener(path), path
    end
  end

  def self.unix path
    Revactor::UNIX.connect path, :filter => FILTERS
  end

  def self.connect uri
    case uri.scheme
    when 'tcp' then tcp uri.host, uri.port
    when 'unix' then unix uri.path
    else fail "unknown URI scheme #{uri.scheme}"
    end
  end

  def self.listen uri, dispatcher
    case uri.scheme
    when 'tcp' then TCPListener.listen dispatcher, uri.host, uri.port
    when 'unix' then UnixListener.listen dispatcher, uri.path
    else fail "unknown URI scheme #{uri.scheme}"
    end
  end
end
end
