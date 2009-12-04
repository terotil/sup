module Redwood

class Server
  attr_reader :index

  def initialize index
    @index = index
  end

  def service w
    Client.new(self, w).run
  end
end

class Server::Client
  attr_reader :server, :wire

  def initialize server, wire
    @server = server
    @wire = wire
  end

  def run
    begin
      while (x = wire.read)
        type, args, = *x
        puts "#{type}: #{args.map { |k,v| "#{k}=#{v.inspect}" } * ', '}"
        method_name = :"request_#{type}"
        if respond_to? method_name
          send method_name, args
        else
          reply_error :tag => args[:tag], :type => :uknown_request, :message => "Unknown request"
        end
      end
    ensure
      wire.close
    end
  end

  ## Requests
  ##
  ## There may be zero or more replies to a request. Multiple requests may be
  ## issued concurrently. <tag> is an opaque object returned in all replies to
  ## the request.

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
  def request_query args
    q = server.index.parse_query args[:query]
    fields = args[:fields]
    offset = args[:offset] || 0
    limit = args[:limit]
    i = 0
    server.index.each_id q do |msgid|
      i += 1
      next unless i > offset
      e = server.index.get_entry msgid
      e[:labels] = e[:labels].to_a
      raw = args[:raw] && server.index.build_message(msgid).raw_message
      reply_message :tag => args[:tag], :message => e, :raw => raw
      break if limit and i >= (offset+limit)
    end
    reply_done :tag => args[:tag]
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
  def request_count args
    q = server.index.parse_query args[:query]
    count = server.index.num_results_for q
    reply_count :tag => args[:tag], :count => count
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
  def request_label args
    reply_error :tag => args[:tag], :type => :unimplemented, :message => "unimplemented"
  end

  # Add request
  #
  # Add a message to the database. <raw> is the normal RFC 2822 message text.
  #
  # Parameters
  # tag: opaque object
  # raw: message data
  #
  # Responses
  # one Done
  def request_add args
    reply_error :tag => args[:tag], :type => :unimplemented, :message => "unimplemented"
  end

  # Stream request
  #
  # Parameters
  # tag: opaque object
  # query: Xapian query string
  #
  # Responses
  # multiple Message
  def request_stream args
    reply_error :tag => args[:tag], :type => :unimplemented, :message => "unimplemented"
  end

  # Cancel request
  #
  # Parameters
  # tag: opaque object
  # target: tag of the request to cancel
  #
  # Responses
  # one Done
  def request_cancel args
    reply_error :tag => args[:tag], :type => :unimplemented, :message => "unimplemented"
  end

  # Done reply
  #
  # Parameters
  # tag: opaque object
  def reply_done args
    wire.write :done, args
  end

  # Message reply
  #
  # Parameters
  # tag: opaque object
  def reply_message args
    wire.write :message, args
  end

  # Count reply
  #
  # Parameters
  # tag: opaque object
  # count: number of messages matched
  def reply_count args
    wire.write :count, args
  end

  # Error reply
  #
  # Parameters
  # tag: opaque object
  # type: symbol
  # message: string
  def reply_error args
    wire.write :error, args
  end
end

end
