require 'sup/actor'

module Redwood
module Server

class StorageActor < Actorized
  def run store
    main_msgloop do |f|
      f.when(T[:put]) { |_,a,data| a << T[:put_done, store.put(data)] }
      f.when(T[:get]) { |_,a,offset| a << T[:got, store.get(offset)] }
    end
    store.close
  end
end

end
end
