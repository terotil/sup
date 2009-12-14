require 'sup/actor'

module Redwood
module Server

class IndexActor < Actorized
  def run index
    main_msgloop do |f|
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
    end
  end
end

end
end
