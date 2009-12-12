# encoding: utf-8
require 'uri'
require 'net/imap'
require 'stringio'
require 'time'
require 'rmail'
require 'cgi'
require 'set'

## TODO: remove synchronized method protector calls; use a Monitor instead
## (ruby's reentrant mutex)

## fucking imap fucking sucks. what the FUCK kind of committee of dunces
## designed this shit.
##
## imap talks about 'unique ids' for messages, to be used for
## cross-session identification. great---just what sup needs! except it
## turns out the uids can be invalidated every time the 'uidvalidity'
## value changes on the server, and 'uidvalidity' can change without
## restriction. it can change any time you log in. it can change EVERY
## time you log in. of course the imap spec "strongly recommends" that it
## never change, but there's nothing to stop people from just setting it
## to the current timestamp, and in fact that's EXACTLY what the one imap
## server i have at my disposal does. thus the so-called uids are
## absolutely useless and imap provides no cross-session way of uniquely
## identifying a message. but thanks for the "strong recommendation",
## guys!
##
## so right now i'm using the 'internal date' and the size of each
## message to uniquely identify it, and i scan over the entire mailbox
## each time i open it to map those things to message ids. that can be
## slow for large mailboxes, and we'll just have to hope that there are
## no collisions. ho ho! a perfectly reasonable solution!
##
## and here's another thing. check out RFC2060 2.2.2 paragraph 5:
##
##   A client MUST be prepared to accept any server response at all
##   times.  This includes server data that was not requested.
##
## yeah. that totally makes a lot of sense. and once again, the idiocy of
## the spec actually happens in practice. you'll request flags for one
## message, and get it interspersed with a random bunch of flags for some
## other messages, including a different set of flags for the same
## message! totally ok by the imap spec. totally retarded by any other
## metric.
##
## fuck you, imap committee. you managed to design something nearly as
## shitty as mbox but goddamn THIRTY YEARS LATER.
module Redwood
class Source

class IMAP < Source
  include SerializeLabelsNicely
  SCAN_INTERVAL = 60 # seconds

  ## upon these errors we'll try to rereconnect a few times
  RECOVERABLE_ERRORS = [ Errno::EPIPE, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError ]

  attr_accessor :username, :password
  yaml_properties :uri, :username, :password, :cur_offset, :usual,
                  :archived, :labels

  def initialize uri, username, password, last_idate=nil, usual=true, archived=false, labels=[]
    raise ArgumentError, "username and password must be specified" unless username && password
    raise ArgumentError, "not an imap uri" unless uri =~ %r!imaps?://!

    super uri, last_idate, usual, archived

    @parsed_uri = URI(uri)
    @username = username
    @password = password
    @imap = nil
    @imap_state = {}
    @ids = []
    @last_scan = nil
    @labels = Set.new((labels || []) - LabelManager::RESERVED_LABELS)
    @say_id = nil
    @mutex = Mutex.new
  end

  def self.suggest_labels_for path
    path =~ /([^\/]*inbox[^\/]*)/i ? [$1.downcase.intern] : []
  end

  def host; @parsed_uri.host; end
  def port; @parsed_uri.port || (ssl? ? 993 : 143); end
  def mailbox
    x = @parsed_uri.path[1..-1]
    (x.nil? || x.empty?) ? 'INBOX' : CGI.unescape(x)
  end
  def ssl?; @parsed_uri.scheme == 'imaps' end

  def check; end # do nothing because anything we do will be too slow,
                 # and we'll catch the errors later.

  ## is this necessary? TODO: remove maybe
  def == o; o.is_a?(IMAP) && o.uri == self.uri && o.username == self.username; end

  def load_header id
    parse_raw_email_header StringIO.new(raw_header(id))
  end

  def load_message id
    RMail::Parser.read raw_message(id)
  end
  
  def each_raw_message_line id
    StringIO.new(raw_message(id)).each { |l| yield l }
  end

  def raw_header id
    unsynchronized_scan_mailbox
    header, flags = get_imap_fields id, 'RFC822.HEADER'
    header.gsub(/\r\n/, "\n")
  end
  synchronized :raw_header

  def store_message date, from_email, &block
    message = StringIO.new
    yield message
    message.string.gsub! /\n/, "\r\n"

    safely { @imap.append mailbox, message.string, [:Seen], Time.now }
  end

  def raw_message id
    unsynchronized_scan_mailbox
    get_imap_fields(id, 'RFC822').first.gsub(/\r\n/, "\n")
  end
  synchronized :raw_message

  def mark_as_deleted ids
    ids = [ids].flatten # accept single arguments
    unsynchronized_scan_mailbox
    imap_ids = ids.map { |i| @imap_state[i] && @imap_state[i][:id] }.compact
    return if imap_ids.empty?
    @imap.store imap_ids, "+FLAGS", [:Deleted]
  end
  synchronized :mark_as_deleted

  def expunge
    @imap.expunge
    unsynchronized_scan_mailbox true
    true
  end
  synchronized :expunge

  def connect
    return if @imap
    safely { } # do nothing!
  end
  synchronized :connect

  def scan_mailbox force=false
    return if !force && @last_scan && (Time.now - @last_scan) < SCAN_INTERVAL
    last_id = safely do
      @imap.examine mailbox
      @imap.responses["EXISTS"].last
    end
    @last_scan = Time.now

    @ids = [] if force
    return if last_id == @ids.length

    range = (@ids.length + 1) .. last_id
    debug "fetching IMAP headers #{range}"
    fetch(range, ['RFC822.SIZE', 'INTERNALDATE', 'FLAGS']).each do |v|
      id = make_id v
      @ids << id
      @imap_state[id] = { :id => v.seqno, :flags => v.attr["FLAGS"] }
    end
    debug "done fetching IMAP headers"
  end
  synchronized :scan_mailbox

  def each
    return unless start_offset

    ids = 
      @mutex.synchronize do
        unsynchronized_scan_mailbox
        @ids
      end

    start = ids.index(cur_offset || start_offset) or raise OutOfSyncSourceError, "Unknown message id #{cur_offset || start_offset}."

    start.upto(ids.length - 1) do |i|
      id = ids[i]
      state = @mutex.synchronize { @imap_state[id] } or next
      self.cur_offset = id 
      labels = { :Flagged => :starred,
                 :Deleted => :deleted
               }.inject(@labels) do |cur, (imap, sup)|
        cur + (state[:flags].include?(imap) ? [sup] : [])
      end

      labels += [:unread] unless state[:flags].include?(:Seen)

      yield id, labels
    end
  end

  def start_offset
    unsynchronized_scan_mailbox
    @ids.first
  end
  synchronized :start_offset

  def end_offset
    unsynchronized_scan_mailbox
    @ids.last + 1
  end
  synchronized :end_offset

  def pct_done; 100.0 * (@ids.index(cur_offset) || 0).to_f / (@ids.length - 1).to_f; end

private

  def fetch ids, fields
    results = safely { @imap.fetch ids, fields }
    good_results = 
      if ids.respond_to? :member?
        results.find_all { |r| ids.member?(r.seqno) && fields.all? { |f| r.attr.member?(f) } }
      else
        results.find_all { |r| ids == r.seqno && fields.all? { |f| r.attr.member?(f) } }
      end

    if good_results.empty?
      raise FatalSourceError, "no IMAP response for #{ids} containing all fields #{fields.join(', ')} (got #{results.size} results)"
    elsif good_results.size < results.size
      warn "Your IMAP server sucks. It sent #{results.size} results for a request for #{good_results.size} messages. What are you using, Binc?"
    end

    good_results
  end

  def unsafe_connect
    say "Connecting to IMAP server #{host}:#{port}..."

    ## apparently imap.rb does a lot of threaded stuff internally and if
    ## an exception occurs, it will catch it and re-raise it on the
    ## calling thread. but i can't seem to catch that exception, so i've
    ## resorted to initializing it in its own thread. surely there's a
    ## better way.
    exception = nil
    ::Thread.new do
      begin
        #raise Net::IMAP::ByeResponseError, "simulated imap failure"
        @imap = Net::IMAP.new host, port, ssl?
        say "Logging in..."

        ## although RFC1730 claims that "If an AUTHENTICATE command fails
        ## with a NO response, the client may try another", in practice
        ## it seems like they can also send a BAD response.
        begin
          raise Net::IMAP::NoResponseError unless @imap.capability().member? "AUTH=CRAM-MD5"
          @imap.authenticate 'CRAM-MD5', @username, @password
        rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError => e
          debug "CRAM-MD5 authentication failed: #{e.class}. Trying LOGIN auth..."
          begin
            raise Net::IMAP::NoResponseError unless @imap.capability().member? "AUTH=LOGIN"
            @imap.authenticate 'LOGIN', @username, @password
          rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError => e
            debug "LOGIN authentication failed: #{e.class}. Trying plain-text LOGIN..."
            @imap.login @username, @password
          end
        end
        say "Successfully connected to #{@parsed_uri}."
      rescue Exception => e
        exception = e
      ensure
        shutup
      end
    end.join

    raise exception if exception
  end

  def say s
    @say_id = BufferManager.say s, @say_id if BufferManager.instantiated?
    info s
  end

  def shutup
    BufferManager.clear @say_id if BufferManager.instantiated?
    @say_id = nil
  end

  def make_id imap_stuff
    # use 7 digits for the size. why 7? seems nice.
    %w(RFC822.SIZE INTERNALDATE).each do |w|
      raise FatalSourceError, "requested data not in IMAP response: #{w}" unless imap_stuff.attr[w]
    end

    msize, mdate = imap_stuff.attr['RFC822.SIZE'] % 10000000, Time.parse(imap_stuff.attr["INTERNALDATE"])
    sprintf("%d%07d", mdate.to_i, msize).to_i
  end

  def get_imap_fields id, *fields
    raise OutOfSyncSourceError, "Unknown message id #{id}" unless @imap_state[id]

    imap_id = @imap_state[id][:id]
    result = fetch(imap_id, (fields + ['RFC822.SIZE', 'INTERNALDATE']).uniq).first
    got_id = make_id result

    ## I've turned off the following sanity check because Microsoft
    ## Exchange fails it.  Exchange actually reports two different
    ## INTERNALDATEs for the exact same message when queried at different
    ## points in time.
    ##
    ## RFC2060 defines the semantics of INTERNALDATE for messages that
    ## arrive via SMTP for via various IMAP commands, but states that
    ## "All other cases are implementation defined.". Great, thanks guys,
    ## yet another useless field.
    ## 
    ## Of course no OTHER imap server I've encountered returns DIFFERENT
    ## values for the SAME message. But it's Microsoft; what do you
    ## expect? If their programmers were any good they'd be working at
    ## Google.

    # raise OutOfSyncSourceError, "IMAP message mismatch: requested #{id}, got #{got_id}." unless got_id == id

    fields.map { |f| result.attr[f] or raise FatalSourceError, "empty response from IMAP server: #{f}" }
  end

  ## execute a block, connected if unconnected, re-connected up to 3
  ## times if a recoverable error occurs, and properly dying if an
  ## unrecoverable error occurs.
  def safely
    retries = 0
    begin
      begin
        unsafe_connect unless @imap
        yield
      rescue *RECOVERABLE_ERRORS => e
        if (retries += 1) <= 3
          @imap = nil
          warn "got #{e.class.name}: #{e.message.inspect}"
          sleep 2
          retry
        end
        raise
      end
    rescue SocketError, Net::IMAP::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
      raise FatalSourceError, "While communicating with IMAP server (type #{e.class.name}): #{e.message.inspect}"
    end
  end

end

end
end
