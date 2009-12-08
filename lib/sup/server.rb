require 'revactor'

module Redwood

class Server
  extend Actorize
  attr_reader :index, :store, :actor

  def initialize index, store
    @index = index
    @store = store
    @stream_lock = Mutex.new
    @stream_subscribers = []
    @actor = Actor.current
    run
  end

  def run
    loop do
      Actor.receive do |filter|
        filter.when(T[:client]) do |_,wire|
          ClientConnection.spawn self, wire
        end
      end
    end
  end

  def stream_subscribe
    q = Queue.new
    @stream_lock.synchronize { @stream_subscribers << q }
    q
  end

  def stream_unsubscribe q
    @stream_lock.synchronize { @stream_subscribers.delete q }
  end

  def stream_notify addr
    @stream_lock.synchronize { @stream_subscribers.each { |q| q << addr } }
  end
end

module Logging
  def log_msg type, args
    puts "#{type}: #{args.map { |k,v| "#{k}=#{v.inspect}" } * ', '}" if $VERBOSE
  end
end

class ClientConnection
  extend Actorize
  include Logging
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
          log_msg type, args
          args ||= {}
          klass = case type
          when :query then QueryHandler
          when :count then CountHandler
          when :label then LabelHandler
          when :add then AddHandler
          when :stream then StreamHandler
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

## Requests
##
## There may be zero or more replies to a request. Multiple requests may be
## issued concurrently. <tag> is an opaque object returned in all replies to
## the request.

class RequestHandler
  extend Actorize
  include Logging
  attr_reader :client, :args, :server, :wire

  def initialize client, args
    @client = client
    @args = args
    @server = client.server
    @wire = client.wire
    run
  end

  def message_from_summary summary
    extract_person = lambda { |p| [p.email, p.name] }
    extract_people = lambda { |ps| ps.map(&extract_person) }
    {
      :message_id => summary.id,
      :date => summary.date,
      :from => extract_person[summary.from],
      :to => extract_people[summary.to],
      :cc => extract_people[summary.cc],
      :bcc => extract_people[summary.bcc],
      :subject => summary.subj,
      :refs => summary.refs,
      :replytos => summary.replytos,
      :labels => summary.labels.to_a,
    }
  end

  # Done reply
  #
  # Parameters
  # tag: opaque object
  def reply_done args
    respond wire, :done, args
  end

  # Message reply
  #
  # Parameters
  # tag: opaque object
  # message:
  #   message_id
  #   date
  #   from
  #   to, cc, bcc: List of [email, name]
  #   subject
  #   refs
  #   replytos
  #   labels
  def reply_message args
    respond wire, :message, args
  end

  # Count reply
  #
  # Parameters
  # tag: opaque object
  # count: number of messages matched
  def reply_count args
    respond wire, :count, args
  end

  # Error reply
  #
  # Parameters
  # tag: opaque object
  # type: symbol
  # message: string
  def reply_error args
    respond wire, :error, args
  end

  def respond wire, type, args={}
    log_msg type, args
    wire.send type, args
  end
end

# Query request
#
# Send a Message reply for each hit on <query>. <offset> and <limit>
# influence which results are returned.
#
# Parameters
# tag: opaque object
# query: Xapian query string
# offset: skip this many messages
# limit: return at most this many messages
# raw: include the raw message text
#
# Responses
# multiple Message
# one Done after all Messages
class QueryHandler < RequestHandler
  def run
    q = server.index.parse_query args[:query]
    fields = args[:fields]
    offset = args[:offset] || 0
    limit = args[:limit]
    i = 0
    server.index.each_summary q do |summary|
      i += 1
      next unless i > offset
      message = message_from_summary summary
      raw = args[:raw] && server.store.get(summary.source_info)
      reply_message :tag => args[:tag], :message => message, :raw => raw
      break if limit and i >= (offset+limit)
    end
    reply_done :tag => args[:tag]
  end
end

# Count request
#
# Send a count reply with the number of hits for <query>.
#
# Parameters
# tag: opaque object
# query: Xapian query string
#
# Responses
# one Count
class CountHandler < RequestHandler
  def run
    q = server.index.parse_query args[:query]
    count = server.index.num_results_for q
    reply_count :tag => args[:tag], :count => count
  end
end

# Label request
#
# Modify the labels on all messages matching <query>.
#
# Parameters
# tag: opaque object
# query: Xapian query string
# add: labels to add
# remove: labels to remove
#
# Responses
# one Done
class LabelHandler < RequestHandler
  def run
    q = server.index.parse_query args[:query]
    add = args[:add] || []
    remove = args[:remove] || []
    server.index.each_summary q do |summary|
      labels = summary.labels - remove + add
      m = Message.parse server.store.get(summary.source_info), :labels => labels, :source_info => summary.source_info
      server.index.update_message_state m
    end

    reply_done :tag => args[:tag]
  end
end

# Add request
#
# Add a message to the database. <raw> is the normal RFC 2822 message text.
#
# Parameters
# tag: opaque object
# raw: message data
# labels: initial labels
#
# Responses
# one Done
class AddHandler < RequestHandler
  def run
    raw = args[:raw]
    labels = args[:labels] || []
    addr = server.store.put raw
    m = Message.parse raw, :labels => labels, :source_info => addr
    server.index.add_message m
    reply_done :tag => args[:tag]
    server.stream_notify addr
  end
end

# Stream request
#
# Parameters
# tag: opaque object
# query: Xapian query string
#
# Responses
# multiple Message
class StreamHandler < RequestHandler
  def run
    q = server.index.parse_query args[:query]
    queue = server.stream_subscribe
    while (addr = queue.deq)
      q[:source_info] = addr
      summary = server.index.each_summary(q).first or next
      raw = args[:raw] && server.store.get(summary.source_info)
      reply_message :tag => args[:tag], :message => message_from_summary(summary), :raw => raw
    end
  end
end

# Cancel request
#
# Parameters
# tag: opaque object
# target: tag of the request to cancel
#
# Responses
# one Done
class CancelHandler < RequestHandler
  def request_cancel args
    reply_error :tag => args[:tag], :type => :unimplemented, :message => "unimplemented"
  end
end

end
