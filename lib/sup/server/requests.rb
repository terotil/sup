## Requests
##
## There may be zero or more replies to a request. Multiple requests may be
## issued concurrently. <tag> is an opaque object returned in all replies to
## the request.

module Redwood::Server

class RequestHandler < Actorized
  attr_reader :client, :args, :dispatcher, :wire

  def initialize client, args
    @client = client
    @args = args
    @dispatcher = client[:dispatcher]
    @wire = client[:wire]
    super()
  end

  def index; dispatcher[:index]; end
  def store; dispatcher[:store]; end
  def server; dispatcher; end

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
    debug_msg type, args
    wire.send type, args
  end

  def parse_query s
    index << T[:parse_query, me, s]
    q = nil
    Actor.receive { |f| f.when(T[:parsed_query]) { |_,x| q = x } }
    q
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
    q = parse_query args[:query]
    fields = args[:fields]
    offset = args[:offset] || 0
    limit = args[:limit]
    finished = false

    index << T[:query, me, q, offset, limit]
    while not finished
      Actor.receive do |f|
        f.when(T[:query_result]) do |_,summary|
          message = message_from_summary summary
          raw = nil
          if args[:raw]
            store << T[:get, me, summary.source_info]
            Actor.receive { |f| f.when(T[:got]) { |_,d| raw = d } }
          end
          reply_message :tag => args[:tag], :message => message, :raw => raw
        end
        f.when(:query_finished) { finished = true }
      end
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
    q = parse_query args[:query]
    count = nil
    index << T[:count, me, q]
    Actor.receive { |f| f.when(T[:counted]) { |_,c| count = c } }
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
    q = parse_query args[:query]
    add = args[:add] || []
    remove = args[:remove] || []
    finished = false

    index << T[:query, me, q, 0, nil]
    while not finished
      Actor.receive do |f|
        f.when(T[:query_result]) do |_,summary|
          labels = summary.labels - remove + add
          store << T[:get, me, summary.source_info]
          raw = nil
          Actor.receive { |f| f.when(T[:got]) { |_,d| raw = d } }
          m = Redwood::Message.parse raw, :labels => labels, :source_info => summary.source_info
          index << T[:add, me, m]
          Actor.receive { |f| f.when(:added) { } }
        end
        f.when(:query_finished) { finished = true }
      end
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
    store << T[:put, me, raw]
    addr = nil
    Actor.receive { |f| f.when(T[:put_done]) { |_,a| addr = a } }
    m = Redwood::Message.parse raw, :labels => labels, :source_info => addr
    index << T[:add, me, m]
    Actor.receive { |f| f.when(:added) {} }
    reply_done :tag => args[:tag]
    server << T[:publish, T[:new_message, addr]]
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
    q = parse_query args[:query]
    server << T[:subscribe, me]
    msgloop do |f|
      f.when(T[:new_message]) do |_,addr|
        q[:source_info] = addr
        index << T[:query, me, q, 0, 1]
        summary = nil
        finished = false
        while not finished
          Actor.receive do |f|
            f.when(T[:query_result]) { |_,x| summary = x }
            f.when(:query_finished) { finished = true }
          end
        end
        next unless summary
        raw = nil
        if args[:raw]
          store << T[:get, me, summary.source_info]
          Actor.receive { |f| f.when(T[:got]) { |_,d| raw = d } }
        end
        reply_message :tag => args[:tag], :message => message_from_summary(summary), :raw => raw
      end
      f.die? T[:cancel, args[:tag]]
    end
  end

  def ensure
    server << T[:unsubscribe, me]
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
  def run
    server << T[:publish, T[:cancel, args[:tag]]]
  end
end

end
