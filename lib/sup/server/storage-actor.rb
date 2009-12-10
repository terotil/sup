require 'revactor'

module Redwood
module Server

class StorageActor
  extend Actorize

  def initialize store
    die = false
    while not die
      Actor.receive do |f|
        f.when(T[:put]) { |_,a,data| a << T[:put_done, store.put(data)] }
        f.when(T[:get]) { |_,a,offset| a << T[:got, store.get(offset)] }
        f.when(:die) { die = true }
      end
    end
    store.close
  end
end

end
end
