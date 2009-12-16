module Redwood::Server

class RequestHandler < Actorized
  attr_reader :client, :args, :dispatcher

  def initialize client, args
    @client = client
    @args = SavingHash.new { |k| args[k.to_s] }
    @dispatcher = client[:dispatcher]
    super()
  end

  def index; dispatcher[:index]; end
  def store; dispatcher[:store]; end
  def server; dispatcher; end

  def reply_done args
    respond client, :done, args
  end

  def reply_message args
    respond client, :message, args
  end

  def reply_count args
    respond client, :count, args
  end

  def reply_error args
    respond client, :error, args
  end

  def respond client, type, args={}
    debug_msg type, args
    client << T[:reply, type, args]
  end

  def put_raw raw
    store << T[:put, me, raw]
    expect T[:put_done], &_2
  end

  def get_raw addr
    store << T[:get, me, addr]
    expect T[:got], &_2
  end

  def index_message m
    index << T[:add, me, m]
    expect :added
  end
end

class QueryHandler < RequestHandler
  def run
    q = args[:query]
    fields = args[:fields]
    offset = args[:offset] || 0
    limit = args[:limit]

    index << T[:query, me, q, offset, limit]
    main_msgloop do |f|
      f.when(T[:query_result]) do |_,summary|
        raw = args[:raw] ? get_raw(summary[:source_info]) : nil
        reply_message :tag => args[:tag], :message => summary, :raw => raw
      end
      f.die? :query_finished
    end
    reply_done :tag => args[:tag]
  end
end

class CountHandler < RequestHandler
  def run
    q = args[:query]
    index << T[:count, me, q]
    count = expect T[:counted], &_2
    reply_count :tag => args[:tag], :count => count
  end
end

class LabelHandler < RequestHandler
  def run
    q = args[:query]
    add = args[:add] || []
    remove = args[:remove] || []

    index << T[:query, me, q, 0, nil]
    main_msgloop do |f|
      f.when(T[:query_result]) do |_,summary|
        labels = summary[:labels] - remove + add
        raw = get_raw summary[:source_info]
        m = Redwood::Message.parse raw, :labels => labels, :source_info => summary[:source_info]
        index_message m
      end
      f.die? :query_finished
    end

    reply_done :tag => args[:tag]
  end

end

class AddHandler < RequestHandler
  def run
    raw = args[:raw]
    raw.force_encoding Encoding::ASCII_8BIT
    labels = args[:labels] || []
    addr = put_raw raw
    m = Redwood::Message.parse raw, :labels => labels, :source_info => addr
    index_message m
    reply_done :tag => args[:tag]
    server << T[:publish, T[:new_message, addr]]
  end
end

class StreamHandler < RequestHandler
  def run
    server << T[:subscribe, me]
    msgloop do |f|
      f.when(T[:new_message]) do |_,addr|
        next unless summary = get_relevant_summary(addr)
        raw = args[:raw] ? get_raw(addr) : nil
        reply_message :tag => args[:tag], :message => summary, :raw => raw
      end
      f.die? T[:cancel, args[:tag]]
    end
  end

  def get_relevant_summary addr
    q = args[:query]
    q = ['and', q, ['term', 'source_info', addr]]
    index << T[:query, me, q, 0, 1]
    summary = nil
    msgloop do |f|
      f.when(T[:query_result]) { |_,x| summary = x }
      f.die? :query_finished
    end
    summary
  end

  def ensure
    server << T[:unsubscribe, me]
  end
end

class CancelHandler < RequestHandler
  def run
    server << T[:publish, T[:cancel, args[:tag]]]
  end
end

end
