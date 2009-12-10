require 'revactor'

module Redwood
module Server

class IndexActor
  extend Actorize

  def initialize index
    die = false
    while not die
      Actor.receive do |f|
        f.when(T[:parse_query]) do |_,a,s|
          a << [:parsed_query, index.parse_query(s)]
        end

        f.when(T[:query]) do |_,a,q,offset,limit|
          index.each_summary(q,offset,limit) { |x| a << T[:query_result, x] }
          a << :query_finished
        end

        f.when(T[:count]) do |_,a,q|
          a << T[:counted, index.count(q)]
        end

        f.when(T[:add]) do |_,a,m|
          index.add_message m
          a << :added
        end

        f.when(:die) { die = true }

        f.when(Object) { |x| raise "unknown object #{x.inspect}" }
      end
    end
  end
end

end
end
