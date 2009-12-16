module Redwood

module Query
  def and *qs
    ['and', *qs]
  end

  def or *qs
    ['or', *qs]
  end

  def not q1, q2
    ['not', q1, q2]
  end

  def term field, value
    ['term', field.to_s, value.to_s]
  end

  Q = self
  def from_opts opts
    labels = ([opts[:label]] + (opts[:labels] || [])).compact
    neglabels = [:spam, :deleted, :killed].reject { |l| (labels.include? l) || opts.member?("load_#{l}".intern) }
    pos_terms, neg_terms = [], []

    pos_terms << term(:type, 'mail')
    pos_terms.concat(labels.map { |l| term(:label,l) })
    pos_terms << opts[:qobj] if opts[:qobj]
    pos_terms << term(:source_info, opts[:source_info]) if opts[:source_info]
    pos_terms << term(:msgid, opts[:msgid]) if opts[:msgid]

    if opts[:participants]
      participant_terms = opts[:participants].map { |p| term(:email,:any, (Redwood::Person === p) ? p.email : p) }
      pos_terms << Q.or(*participant_terms)
    end

    neg_terms.concat(neglabels.map { |l| term(:label,l) })

    pos_query = Q.and(*pos_terms)
    neg_query = Q.or(*neg_terms)

    if neg_query.empty?
      pos_query
    else
      Q.not(pos_query, neg_query)
    end
  end

  module_function :from_opts, :and, :or, :not, :term
end

end
