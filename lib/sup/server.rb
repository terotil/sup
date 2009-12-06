module Redwood

class Server
  attr_reader :index, :store, :source

  def initialize index, store
    @index = index
    @store = store
    @source = StorageSource.new @store
  end

  def client w
    Client.new(self, w)
  end

  def service w
    begin
      c = client(w)
      while c.serve; end
    rescue Errno::ECONNRESET, Errno::EPIPE
    end
  end
end

class Server::Client
  attr_reader :server, :wire

  def initialize server, wire
    @server = server
    @wire = wire
  end

  def serve
    x = wire.read or return false
    type, args, = *x
    args ||= {}
    log_msg type, args
    method_name = :"request_#{type}"
    if respond_to? method_name
      send method_name, args
    else
      reply_error :tag => args[:tag], :type => :uknown_request, :message => "Unknown request"
    end
    true
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
    server.index.each_summary q do |summary|
      i += 1
      next unless i > offset
      extract_person = lambda { |p| [p.email, p.name] }
      extract_people = lambda { |ps| ps.map(&extract_person) }
      message = {
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
      raw = args[:raw] && server.store.get(summary.source_info)
      reply_message :tag => args[:tag], :message => message, :raw => raw
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
  def request_add args
    raw = args[:raw]
    labels = args[:labels] || []
    addr = server.store.put raw
    m = Message.parse raw, :labels => labels, :source_info => addr
    server.index.add_message m
    reply_done :tag => args[:tag]
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
    wire.write type, args
  end

  def log_msg type, args
    puts "#{type}: #{args.map { |k,v| "#{k}=#{v.inspect}" } * ', '}" if $VERBOSE
  end
end

class StorageSource < Source
  def initialize store
    @store = store
  end

  def load_header offset
    parse_raw_email_header StringIO.new(raw_header(offset))
  end

  def load_message offset
    RMail::Parser.read raw_message(offset)
  end

  def raw_header offset
    io = StringIO.new raw_message(offset)
    ret = ""
    until io.eof? || (l = io.gets) =~ /^\r*$/
      ret << l
    end
    ret
  end

  def raw_message offset
    @store.get offset
  end
end

end
