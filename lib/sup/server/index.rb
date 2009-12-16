# encoding: utf-8
require 'xapian'
require 'set'

module Redwood
module Server

class Index
  STEM_LANGUAGE = "english"
  INDEX_VERSION = '3'

  ## dates are converted to integers for xapian, and are used for document ids,
  ## so we must ensure they're reasonably valid. this typically only affect
  ## spam.
  MIN_DATE = Time.at 0
  MAX_DATE = Time.at(2**31-1)

  hook "custom-search", <<EOS
Executes before a string search is applied to the index,
returning a new search string.
Variables:
  subs: The string being searched.
EOS

  def initialize path=File.join(Redwood::Server::BASE_DIR, 'xapian')
    @index_mutex = Monitor.new

    if File.exists? path
      @xapian = Xapian::WritableDatabase.new(path, Xapian::DB_OPEN)
      db_version = @xapian.get_metadata 'version'
      db_version = '0' if db_version.empty?
      if db_version != INDEX_VERSION
        fail "This Sup version expects a v#{INDEX_VERSION} index, but you have an existing v#{db_version} index. Please downgrade to your previous version and dump your labels before upgrading to this version (then run sup-sync --restore)."
      end
    else
      @xapian = Xapian::WritableDatabase.new(path, Xapian::DB_CREATE)
      @xapian.set_metadata 'version', INDEX_VERSION
    end
    @enquire = Xapian::Enquire.new @xapian
    @enquire.weighting_scheme = Xapian::BoolWeight.new
    @enquire.docid_order = Xapian::Enquire::ASCENDING
  end

  def contains_id? id
    find_docid(id) && true
  end

  def build_message id
    entry = get_entry id
    return unless entry

    source = SourceManager[entry[:source_id]]
    raise "invalid source #{entry[:source_id]}" unless source

    m = Message.new :source => source, :source_info => entry[:source_info],
                    :labels => entry[:labels], :snippet => entry[:snippet]

    mk_person = lambda { |x| Redwood::Person.new(*x.reverse!) }
    entry[:from] = mk_person[entry[:from]]
    entry[:to].map!(&mk_person)
    entry[:cc].map!(&mk_person)
    entry[:bcc].map!(&mk_person)

    m.load_from_index! entry
    m
  end

  def add_message m; sync_message m, true end
  def update_message m; sync_message m, true end
  def update_message_state m; sync_message m, false end

  def debug_check_entry e
    return unless DEBUG_ENCODING
    begin
      e[:message_id].check
      e[:snippet].check if e[:snippet]
      ([e[:from]] + e[:to] + e[:cc] + e[:bcc]).each do |email,name|
        email.check if email
        name.check if name
      end
      e[:subject].check if e[:subject]
      (e[:refs] + e[:replytos]).each { |s| s.check }
    rescue String::CheckError
      puts "Invalid index entry:"
      pp e
      raise
    end
  end

  def count query={}
    xapian_query = build_xapian_query query
    matchset = run_query xapian_query, 0, 0, 100
    matchset.matches_estimated
  end

  def each_summary query, offset, limit
    xapian_query = build_xapian_query query
    rs = run_query_summaries xapian_query, offset, limit
    rs.each { |r| yield r }
    true
  end

  def each_message_in_thread_for m, opts={}
    # TODO thread by subject
    return unless doc = find_doc(m.id)
    queue = doc.value(THREAD_VALUENO).split(',')
    msgids = [m.id]
    seen_threads = Set.new
    seen_messages = Set.new [m.id]
    while not queue.empty?
      thread_id = queue.pop
      next if seen_threads.member? thread_id
      return false if thread_killed? thread_id
      seen_threads << thread_id
      docs = term_docids(mkterm(:thread, thread_id)).map { |x| @xapian.document x }
      docs.each do |doc|
        msgid = doc.value MSGID_VALUENO
        next if seen_messages.member? msgid
        msgids << msgid
        seen_messages << msgid
        queue.concat doc.value(THREAD_VALUENO).split(',')
      end
    end
    msgids.each { |id| yield id, lambda { build_message id } }
    true
  end

  #private

  # Stemmed
  NORMAL_PREFIX = {
    :subject    => 'S',
    :body       => 'B',
    :from_name  => 'FN',
    :to_name    => 'TN',
    :name       => 'N',
    :attachment => 'A',
  }

  # Unstemmed
  BOOLEAN_PREFIX = {
    :type => 'K',
    :from_email => 'FE',
    :to_email => 'TE',
    :email => 'E',
    :date => 'D',
    :label => 'L',
    :attachment_extension => 'O',
    :msgid => 'Q',
    :thread => 'H',
    :ref => 'R',
    :source_info => 'I',
  }

  PREFIX = NORMAL_PREFIX.merge BOOLEAN_PREFIX

  MSGID_VALUENO = 0
  THREAD_VALUENO = 1
  DATE_VALUENO = 2

  MAX_TERM_LENGTH = 245

  # Xapian can very efficiently sort in ascending docid order. Sup always wants
  # to sort by descending date, so this method maps between them. In order to
  # handle multiple messages per second, we use a logistic curve centered
  # around MIDDLE_DATE so that the slope (docid/s) is greatest in this time
  # period. A docid collision is not an error - the code will pick the next
  # smallest unused one.
  DOCID_SCALE = 2.0**32
  TIME_SCALE = 2.0**27
  MIDDLE_DATE = Time.gm(2011)
  def assign_docid m, truncated_date
    t = (truncated_date.to_i - MIDDLE_DATE.to_i).to_f
    docid = (DOCID_SCALE - DOCID_SCALE/(Math::E**(-(t/TIME_SCALE)) + 1)).to_i
    while docid > 0 and docid_exists? docid
      docid -= 1
    end
    docid > 0 ? docid : nil
  end

  # XXX is there a better way?
  def docid_exists? docid
    begin
      @xapian.doclength docid
      true
    rescue RuntimeError #Xapian::DocNotFoundError
      raise unless $!.message =~ /DocNotFoundError/
      false
    end
  end

  def term_docids term
    @xapian.postlist(term).map { |x| x.docid }
  end

  def find_docid id
    docids = term_docids(mkterm(:msgid,id))
    fail unless docids.size <= 1
    docids.first
  end

  def find_doc id
    return unless docid = find_docid(id)
    @xapian.document docid
  end

  def get_entry id
    return unless doc = find_doc(id)
    entry = Marshal.load doc.data
    debug_check_entry entry
    entry
  end

  def thread_killed? thread_id
    not run_query(Q.new(Q::OP_AND, mkterm(:thread, thread_id), mkterm(:label, :Killed)), 0, 1).empty?
  end

  def run_query xapian_query, offset, limit, checkatleast=0
    @enquire.query = xapian_query
    @enquire.mset(offset, limit, checkatleast)
  end

  def run_query_summaries xapian_query, offset, limit
    matchset = run_query xapian_query, offset, limit
    matchset.matches.map { |r| build_summary r.document }
  end

  def build_summary doc
    e = Marshal.load doc.data
    return unless e

    mk_person = lambda { |x| Redwood::Person.new(*x.reverse!) }

    Redwood::MessageSummary.new :id => e[:message_id], :from => mk_person[e[:from]],
                       :date => e[:date], :subj => e[:subject],
                       :to => e[:to].map(&mk_person), :cc => e[:cc].map(&mk_person),
                       :bcc => e[:bcc].map(&mk_person),
                       :refs => e[:refs], :replytos => e[:replytos],
                       :labels => e[:labels], :source_info => e[:source_info],
                       :snippet => (e[:snippet]||'')
  end

  ## This is awful. We want the clients to do the bulk of the work of parsing
  ## the queries so that they can reliably modify them, but we can't expect
  ## them to reimplement the exact scheme that Xapian's TermGenerator and
  ## QueryParser use. Since we use TermGenerator, we need to reconstruct the
  ## query string and run QueryParser on it.
  def build_xapian_query q
    str = query2str q
    qp = Xapian::QueryParser.new
    qp.stemmer = Xapian::Stem.new(STEM_LANGUAGE)
    qp.stemming_strategy = Xapian::QueryParser::STEM_SOME
    qp.default_op = Xapian::Query::OP_AND
    qp.add_valuerangeprocessor(Xapian::NumberValueRangeProcessor.new(DATE_VALUENO, 'date:', true))
    NORMAL_PREFIX.each { |k,v| qp.add_prefix k.to_s, v }
    BOOLEAN_PREFIX.each { |k,v| qp.add_boolean_prefix k.to_s, v }
    xapian_query = qp.parse_query(str, Xapian::QueryParser::FLAG_PHRASE|Xapian::QueryParser::FLAG_BOOLEAN|Xapian::QueryParser::FLAG_LOVEHATE|Xapian::QueryParser::FLAG_WILDCARD, PREFIX[:body])
    fail if xapian_query.nil? or xapian_query.empty?
    debug "#{q.inspect} -> #{xapian_query.description}"
    xapian_query
  end

  def query2str q
    type, *args = *q
    case type
    when 'and', 'or', 'not'
      op = type.upcase
      args.map { |x| '(' + query2str(x) + ')' } * " #{op} "
    when 'term'
      args * ':'
    else
      fail "unknown query type #{type.inspect}"
    end
  end

  def sync_message m, overwrite
    doc = find_doc(m.id)
    existed = doc != nil
    doc ||= Xapian::Document.new
    do_index_static = overwrite || !existed
    old_entry = !do_index_static && doc.entry
    snippet = do_index_static ? m.snippet : old_entry[:snippet]

    entry = {
      :message_id => m.id,
      :source_info => m.source_info,
      :date => truncate_date(m.date),
      :snippet => snippet,
      :labels => m.labels.to_a,
      :from => [m.from.email, m.from.name],
      :to => m.to.map { |p| [p.email, p.name] },
      :cc => m.cc.map { |p| [p.email, p.name] },
      :bcc => m.bcc.map { |p| [p.email, p.name] },
      :subject => m.subj,
      :refs => m.refs.to_a,
      :replytos => m.replytos.to_a,
    }

    if do_index_static
      doc.clear_terms
      doc.clear_values
      index_message_static m, doc, entry
    end

    index_message_threading doc, entry, old_entry
    index_message_labels doc, entry[:labels], (do_index_static ? [] : old_entry[:labels])
    doc.entry = entry

    unless docid = existed ? doc.docid : assign_docid(m, truncate_date(m.date))
      # Could be triggered by spam
      warn "docid underflow, dropping #{m.id.inspect}"
      return
    end
    @xapian.replace_document docid, doc

    true
  end

  ## Index content that can't be changed by the user
  def index_message_static m, doc, entry
    # Person names are indexed with several prefixes
    person_termer = lambda do |d|
      lambda do |p|
        [:"#{d}_name", :name, :body].each do |x|
          doc.index_text p.name, PREFIX[x]
        end if p.name
        [d, :any].each { |x| doc.add_term mkterm(:email, x, p.email) }
      end
    end

    person_termer[:from][m.from] if m.from
    (m.to+m.cc+m.bcc).each(&(person_termer[:to]))

    # Full text search content
    subject_text = m.indexable_subject
    body_text = m.indexable_body
    doc.index_text subject_text, PREFIX[:subject]
    doc.index_text subject_text, PREFIX[:body]
    doc.index_text body_text, PREFIX[:body]
    m.attachments.each { |a| doc.index_text a, PREFIX[:attachment] }

    # Miscellaneous terms
    doc.add_term mkterm(:date, m.date) if m.date
    doc.add_term mkterm(:type, 'mail')
    doc.add_term mkterm(:msgid, m.id)
    m.attachments.each do |a|
      a =~ /\.(\w+)$/ or next
      doc.add_term mkterm(:attachment_extension, $1)
    end
    doc.add_term mkterm(:source_info, m.source_info)

    # Date value for range queries
    date_value = begin
      Xapian.sortable_serialise m.date.to_i
    rescue TypeError
      Xapian.sortable_serialise 0
    end

    doc.add_value MSGID_VALUENO, m.id
    doc.add_value DATE_VALUENO, date_value
  end

  def index_message_labels doc, new_labels, old_labels
    return if new_labels == old_labels
    added = new_labels.to_a - old_labels.to_a
    removed = old_labels.to_a - new_labels.to_a
    added.each { |t| doc.add_term mkterm(:label,t) }
    removed.each { |t| doc.remove_term mkterm(:label,t) }
  end

  ## Assign a set of thread ids to the document. This is a hybrid of the runtime
  ## search done by the Ferret index and the index-time union done by previous
  ## versions of the Xapian index. We first find the thread ids of all messages
  ## with a reference to or from us. If that set is empty, we use our own
  ## message id. Otherwise, we use all the thread ids we previously found. In
  ## the common case there's only one member in that set, but if we're the
  ## missing link between multiple previously unrelated threads we can have
  ## more. Index#each_message_in_thread_for follows the thread ids when
  ## searching so the user sees a single unified thread.
  def index_message_threading doc, entry, old_entry
    return if old_entry && (entry[:refs] == old_entry[:refs]) && (entry[:replytos] == old_entry[:replytos])
    children = term_docids(mkterm(:ref, entry[:message_id])).map { |docid| @xapian.document docid }
    parent_ids = entry[:refs] + entry[:replytos]
    parents = parent_ids.map { |id| find_doc id }.compact
    thread_members = SavingHash.new { [] }
    (children + parents).each do |doc2|
      thread_ids = doc2.value(THREAD_VALUENO).split ','
      thread_ids.each { |thread_id| thread_members[thread_id] << doc2 }
    end
    thread_ids = thread_members.empty? ? [entry[:message_id]] : thread_members.keys
    thread_ids.each { |thread_id| doc.add_term mkterm(:thread, thread_id) }
    parent_ids.each { |ref| doc.add_term mkterm(:ref, ref) }
    doc.add_value THREAD_VALUENO, (thread_ids * ',')
  end

  def truncate_date date
    if date < MIN_DATE
      debug "warning: adjusting too-low date #{date} for indexing"
      MIN_DATE
    elsif date > MAX_DATE
      debug "warning: adjusting too-high date #{date} for indexing"
      MAX_DATE
    else
      date
    end
  end

  # Construct a Xapian term
  def mkterm type, *args
    case type.to_sym
    when :label, :type, :attachment_extension
      PREFIX[type] + args[0].to_s.downcase
    when :date
      PREFIX[type] + args[0].getutc.strftime("%Y%m%d%H%M%S")
    when :email
      case args[0]
      when :from then PREFIX[:from_email]
      when :to then PREFIX[:to_email]
      when :any then PREFIX[:email]
      else raise "Invalid email term type #{args[0]}"
      end + args[1].to_s.downcase
    when :msgid, :ref, :thread
      PREFIX[type] + args[0][0...(MAX_TERM_LENGTH-1)]
    when :source_info
      PREFIX[type] + args[0].to_s
    when *NORMAL_PREFIX.keys
      stemmer = Xapian::Stem.new STEM_LANGUAGE
      PREFIX[type] + stemmer.call(args[0].to_s)
    else
      raise "Invalid term type #{type}"
    end
  end
end

end
end

class Xapian::Document
  def entry
    Marshal.load data
  end

  def entry=(x)
    self.data = Marshal.dump x
  end

  def index_text text, prefix, weight=1
    term_generator = Xapian::TermGenerator.new
    term_generator.stemmer = Xapian::Stem.new(Redwood::Server::Index::STEM_LANGUAGE)
    term_generator.document = self
    term_generator.index_text text, weight, prefix
  end

  alias old_add_term add_term
  def add_term term
    if term.length <= Redwood::Server::Index::MAX_TERM_LENGTH
      old_add_term term
    else
      warn "dropping excessively long term #{term}"
    end
  end
end
