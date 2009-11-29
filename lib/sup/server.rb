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
        method_name = :"req_#{type}"
        if respond_to? method_name
          send method_name, args
        else
          warn "invalid message type #{type}"
        end
      end
    ensure
      wire.close
    end
  end

  def req_query args
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
      e.reject! { |k,v| !fields.member? k } if fields
      wire.write :document, :tag => args[:tag], :document => e
      break if limit and i >= limit
    end
    wire.write :done, :tag => args[:tag]
  end

  def req_count args
    q = server.index.parse_query args[:query]
    count = server.index.num_results_for q
    wire.write :count, :tag => args[:tag], :count => count
  end

  def req_modify args
  end

  def req_add args
  end

  def req_stream args
  end

  def req_cancel args
  end
end

end
