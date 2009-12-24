require 'sup/actor'

module Redwood::Server

class Dispatcher < Actorized
  def run index, store
    self[:index] = index
    self[:store] = store
    @subscribers = []
    main_msgloop do |f|
      f.when(T[:client]) { |_,wire| ClientConnection.spawn_link me, wire }
      f.when(T[:subscribe]) { |_,q| @subscribers << q }
      f.when(T[:unsubscribe]) { |_,q| @subscribers.delete q }
      f.when(T[:publish]) { |_,m| @subscribers.each { |q| q << m } }
    end
  end
end

class ClientConnection < Actorized
  def run dispatcher, wire
    self[:dispatcher] = dispatcher
    self[:wire] = wire
    wire.controller = Actor.current
    wire.active = true
    wire.write []
    main_msgloop do |f|
      f.when(T[Case::Any.new(:tcp, :unix), wire]) do |_,_,m|
        type, args, = m
        debug_msg type, args
        args ||= {}
        klass = case type
        when 'query' then QueryHandler
        when 'count' then CountHandler
        when 'label' then LabelHandler
        when 'add' then AddHandler
        when 'stream' then StreamHandler
        when 'cancel' then CancelHandler
        else
          puts "unknown request #{type.inspect}"
          #reply_error :tag => args[:tag], :type => :uknown_request, :message => "Unknown request"
          nil
        end
        klass.spawn_link me, args unless klass.nil?
      end

      f.when(T[:reply]) do |_,type,args|
        wire.write [[type,args]]
      end

      f.die? T[:unix_closed]
      f.die? T[:tcp_closed]
    end
  end
end

end
