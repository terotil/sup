# encoding: utf-8
require 'stringio'
require 'sup/person'
require 'sup/source'
require 'sup/source/maildir'

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
    raw.force_encoding Encoding::ASCII_8BIT
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

  def mbox
    str = ""
    @msgs.each do |m|
      str << "From test@example.com #{Time.now}"
      m.each_line do |l|
        l = '>' + l if l =~ /From /
        str << l
      end
    end
    str
  end

  ## NB the message sizes or mtimes need to be different for maildir to work
  ## XXX fix the above
  def make_maildir path
    %w(cur new tmp).each { |x| FileUtils.mkdir_p(path + '/' + x) }
    source = Redwood::Source::Maildir.new("maildir:" + path)
    @msgs.each do |m|
      source.store_message Time.now, "make_maildir@example.com" do |io|
        io.write m
      end
      sleep 1.1
    end
  end
end

module NormalMessages
  extend MessageMaker
  msg :id => '1@example.com', :body => 'CountTestTerm QueryOrderingTestTerm', :date => Time.utc(2009, 10, 5)
  msg :id => '2@example.com', :body => 'QueryTestTerm QueryOrderingTestTerm', :date => Time.utc(2009, 11, 22)
  msg :id => '3@example.com', :body => 'QueryTestTerm QueryOrderingTestTerm', :date => Time.utc(2009, 9, 3)
end

module MoreMessages
  extend MessageMaker
  msg :id => '4@example.com', :body => 'nothing'
  msg :id => '5@example.com', :body => 'nothing'
end
