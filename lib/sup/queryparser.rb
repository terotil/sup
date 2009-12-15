module Redwood

module QueryParser
  DEFAULT_FIELD = :body

  class ParseError < StandardError; end

  def parse str
    tokens = str.split
    pos_terms = []
    neg_terms = []
    tokens.each do |x|
      pos = true
      if x[0] == '-'
        x = x[1..-1]
        pos = false
      end
      xs = x.split(':', 2)
      f, v = *(xs[1] ? xs : [DEFAULT_FIELD, xs[0]])
      term = ['term', f, v]
      (pos ? pos_terms : neg_terms) << term
    end

    if neg_terms.empty?
      ['and', *pos_terms]
    else
      ['not', pos_terms, neg_terms]
    end
  end

  def validate q
    fail "query is nil" if q.nil?
  end

  module_function :parse, :validate
end

end
