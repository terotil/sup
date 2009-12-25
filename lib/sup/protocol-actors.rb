# encoding: utf-8
require 'sup/actor'
require 'pp'

module Redwood
module Protocol
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
      Revactor::TCP.listen host, port
    end

    def self.listen server, host, port
      spawn server, listener(host, port)
    end
  end

  def self.tcp host, port
    Revactor::TCP.connect host, port
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
      Revactor::UNIX.listen path
    end

    def self.listen server, path
      spawn server, listener(path), path
    end
  end

  def self.unix path
    Revactor::UNIX.connect path
  end

  class SingleLineBuffer
    def initialize
      @buf = ''
    end

    def << data
      fail unless @buf
      @buf << data
      if i = @buf.index("\n")
        l = @buf.slice!(0..i)
        remaining = @buf
        @buf = nil
        [l,remaining]
      else
        nil
      end
    end
  end

  class ConnectionActor < Actorized
    def run s, controller
      @s = s
      @controller = controller
      @filter = nil
      @version_buf = SingleLineBuffer.new

      @s.controller = me
      @s.active = true
      negotiate
      fail unless @filter

      main_msgloop do |f|
        f.when(T[Case::Any.new(:tcp, :unix), @s]) do |_,_,data|
          debug "#{me.inspect} read chunk #{data.inspect}"
          @filter.decode(data).each { |m| forward m }
        end

        f.when T[Case::Any.new(:tcp_closed, :unix_closed)] do
          @controller << :die
          throw :die
        end

        f.when(T[:msg, @controller]) do |_,_,m|
          debug "#{me.inspect} writing message #{m.inspect}"
          @s.write @filter.encode(m)
        end
      end
    end

    def negotiate
      debug "#{me.inspect} negotiating"
      msgloop do |f|
        f.when(T[Case::Any.new(:tcp, :unix), @s]) do |pr,_,data|
          debug "#{me.inspect} negotiate got chunk #{data.inspect}"
          l, remaining = @version_buf << data
          debug "l=#{l.inspect}, remaining=#{remaining.inspect}"
          if l
            receive_version l
            me << T[pr, @s, remaining] unless remaining.empty?
            throw :die
          end
        end
      end
    end

    def forward m
      debug "#{me.inspect} forwarding message #{m.inspect}"
      @controller << T[:msg, me, m]
    end

    def receive_version l
      encodings, extensions = Redwood::Protocol.parse_version l
      encoding = Redwood::Protocol.choose_encoding encodings
      debug "#{me.inspect} chose #{encoding}"
      @filter = Redwood::Protocol.create_filter encoding
      @s.write(Redwood::Protocol.version_string([encoding], extensions) + "\n")
    end
  end

  class ServerConnectionActor < ConnectionActor
    def negotiate
      debug "#{me.inspect} negotiating"
      @s.write(Redwood::Protocol.version_string + "\n")
      msgloop do |f|
        f.when(T[Case::Any.new(:tcp, :unix), @s]) do |pr,_,data|
          debug "#{me.inspect} negotiate got chunk #{data.inspect}"
          l, remaining = @version_buf << data
          if l
            receive_version l
            me << T[pr, @s, remaining] unless remaining.empty?
            throw :die
          end
        end
      end
    end

    def receive_version l
      encodings, extensions = Redwood::Protocol.parse_version l
      fail unless encodings.size == 1
      debug "#{me.inspect} chose #{encodings.first}"
      @filter = Redwood::Protocol.create_filter encodings.first
    end
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
