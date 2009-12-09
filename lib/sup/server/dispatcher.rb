module Redwood::Server

class Dispatcher
  extend Actorize
  attr_reader :index, :store, :actor

  def initialize index, store
    @index = index
    @store = store
    @subscribers = []
    @actor = Actor.current
    run
  end

  def run
    loop do
      Actor.receive do |filter|
        filter.when(T[:client]) do |_,wire|
          ClientConnection.spawn self, wire
        end
        filter.when(T[:subscribe]) { |_,q| @subscribers << q }
        filter.when(T[:unsubscribe]) { |_,q| @subscribers.delete q }
        filter.when(T[:publish]) { |_,m| @subscribers.each { |q| q << m } }
      end
    end
  end
end

class ClientConnection
  extend Actorize
  attr_reader :server, :wire, :actor

  def initialize server, wire
    @server = server
    @wire = wire
    @actor = Actor.current
    run
  end

  def run
    @wire.controller = Actor.current
    @wire.active = true
    loop do
      Actor.receive do |filter|
        filter.when(T[Case::Any.new(:tcp, :unix), @wire]) do |_,_,m|
          type, args, = m
          debug_msg type, args
          args ||= {}
          klass = case type
          when :query then QueryHandler
          when :count then CountHandler
          when :label then LabelHandler
          when :add then AddHandler
          when :stream then StreamHandler
          when :cancel then CancelHandler
          else
            puts "unknown request #{type.inspect}"
            #reply_error :tag => args[:tag], :type => :uknown_request, :message => "Unknown request"
            nil
          end
          klass.spawn self, args unless klass.nil?
        end
      end
    end
  end
end

end
