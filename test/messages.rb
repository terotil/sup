module MessageMaker
  Person = Redwood::Person

  SKELETON = {
    :date => Time.utc(2009, 12, 4),
    :from => Person.new('Sender', 'sender@example.com'),
    :to => Person.new('Recipient', 'recipient@example.com'),
    :subject => 'subject',
    :message_id => nil,
    :refs => [],
    :replytos => [],
    :body => 'body'
  }

  def msg h
    h = SKELETON.merge h
    h[:message_id] ||= h[:id]
    h.delete :id
    fail 'message_id required' unless h[:message_id]
    raw = make_raw h
    msg_raw raw
  end

  def msg_raw raw
    @msgs ||= []
    @msgs << raw
  end

  def msgs
    @msgs ||= []
    @msgs
  end

  def make_raw h
    str = ""
    s = StringIO.new str
    s.binmode
    h.each do |k,v|
      next if k == :body
      k = k.to_s.gsub('_', '-').capitalize
      s.puts "#{k}: #{v}"
    end
    s.puts
    s.puts h[:body] if h[:body]
    str
  end
end

module NormalMessages
  extend MessageMaker
  msg :id => '1@example.com', :body => 'CountTestTerm'
end
