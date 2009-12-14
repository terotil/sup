require 'sup/server/index'

module Redwood

module QueryParser
  I = Redwood::Server::Index

  class ParseError < StandardError; end

  def parse_query s
    query = {}

    subs = $hooks.run("custom-search", :subs => s) || s
    subs = subs.gsub(/\b(to|from):(\S+)\b/) do
      field, name = $1, $2
      if(p = $contacts.contact_for(name))
        [field, p.email]
      elsif name == "me"
        [field, "(" + $accounts.user_emails.join("||") + ")"]
      else
        [field, name]
      end.join(":")
    end

    ## if we see a label:deleted or a label:spam term anywhere in the query
    ## string, we set the extra load_spam or load_deleted options to true.
    ## bizarre? well, because the query allows arbitrary parenthesized boolean
    ## expressions, without fully parsing the query, we can't tell whether
    ## the user is explicitly directing us to search spam messages or not.
    ## e.g. if the string is -(-(-(-(-label:spam)))), does the user want to
    ## search spam messages or not?
    ##
    ## so, we rely on the fact that turning these extra options ON turns OFF
    ## the adding of "-label:deleted" or "-label:spam" terms at the very
    ## final stage of query processing. if the user wants to search spam
    ## messages, not adding that is the right thing; if he doesn't want to
    ## search spam messages, then not adding it won't have any effect.
    query[:load_spam] = true if subs =~ /\blabel:spam\b/
    query[:load_deleted] = true if subs =~ /\blabel:deleted\b/

    ## gmail style "is" operator
    subs = subs.gsub(/\b(is|has):(\S+)\b/) do
      field, label = $1, $2
      case label
      when "read"
        "-label:unread"
      when "spam"
        query[:load_spam] = true
        "label:spam"
      when "deleted"
        query[:load_deleted] = true
        "label:deleted"
      else
        "label:#{$2}"
      end
    end

    ## gmail style attachments "filename" and "filetype" searches
    subs = subs.gsub(/\b(filename|filetype):(\((.+?)\)\B|(\S+)\b)/) do
      field, name = $1, ($3 || $4)
      case field
      when "filename"
        debug "filename: translated #{field}:#{name} to attachment:\"#{name.downcase}\""
        "attachment:\"#{name.downcase}\""
      when "filetype"
        debug "filetype: translated #{field}:#{name} to attachment_extension:#{name.downcase}"
        "attachment_extension:#{name.downcase}"
      end
    end

    if $have_chronic
      lastdate = 2<<32 - 1
      firstdate = 0
      subs = subs.gsub(/\b(before|on|in|during|after):(\((.+?)\)\B|(\S+)\b)/) do
        field, datestr = $1, ($3 || $4)
        realdate = Chronic.parse datestr, :guess => false, :context => :past
        if realdate
          case field
          when "after"
            debug "chronic: translated #{field}:#{datestr} to #{realdate.end}"
            "date:#{realdate.end.to_i}..#{lastdate}"
          when "before"
            debug "chronic: translated #{field}:#{datestr} to #{realdate.begin}"
            "date:#{firstdate}..#{realdate.end.to_i}"
          else
            debug "chronic: translated #{field}:#{datestr} to #{realdate}"
            "date:#{realdate.begin.to_i}..#{realdate.end.to_i}"
          end
        else
          raise ParseError, "can't understand date #{datestr.inspect}"
        end
      end
    end

    ## limit:42 restrict the search to 42 results
    subs = subs.gsub(/\blimit:(\S+)\b/) do
      lim = $1
      if lim =~ /^\d+$/
        query[:limit] = lim.to_i
        ''
      else
        raise ParseError, "non-numeric limit #{lim.inspect}"
      end
    end

    qp = Xapian::QueryParser.new
    qp.stemmer = Xapian::Stem.new(I::STEM_LANGUAGE)
    qp.stemming_strategy = Xapian::QueryParser::STEM_SOME
    qp.default_op = Xapian::Query::OP_AND
    qp.add_valuerangeprocessor(Xapian::NumberValueRangeProcessor.new(I::DATE_VALUENO, 'date:', true))
    I::NORMAL_PREFIX.each { |k,v| qp.add_prefix k, v }
    I::BOOLEAN_PREFIX.each { |k,v| qp.add_boolean_prefix k, v }
    xapian_query = qp.parse_query(subs, Xapian::QueryParser::FLAG_PHRASE|Xapian::QueryParser::FLAG_BOOLEAN|Xapian::QueryParser::FLAG_LOVEHATE|Xapian::QueryParser::FLAG_WILDCARD, PREFIX['body'])

    raise ParseError if xapian_query.nil? or xapian_query.empty?
    xapian_query
  end
end

end
