require 'socket'
require 'revactor'
require 'stringio'
require 'bert'

class Revactor::TCP::Socket
  def send *o
    write o
  end
end

class Revactor::UNIX::Socket
  def send *o
    write o
  end
end

module Redwood

module Protocol
  DEFAULT_TCP_PORT = 2734

  class BERTFilter
    def encode *o
      BERT.encode(o).tap { |x| x.force_encoding Encoding::ASCII_8BIT }
    end

    def decode s
      [BERT.decode(s)]
    end
  end

  FILTERS = [T[Revactor::Filter::Packet, 4], BERTFilter]

  class GenericListener
    extend Actorize

    def initialize server, l, accept
      l.controller = l.instance_eval { @receiver = Actor.current }
      l.active = true
      die = false
      while not die
        l.enable unless l.enabled?
        Actor.receive do |f|
          f.when(accept) do |_, _, sock|
            server << T[:client, sock]
          end
          f.when(:die) { die = true }
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
    def initialize server, listener
      super server, listener, T[:unix_connection, listener]
    end
    
    def self.listener path
      Revactor::UNIX.listen path, :filter => FILTERS
    end

    def self.listen server, path
      spawn server, listener(path)
    end
  end

  def self.unix path
    Revactor::UNIX.connect path, :filter => FILTERS
  end
end

end
