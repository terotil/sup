# encoding: utf-8
## Index interface, subclassed by Ferret indexer.

require 'fileutils'

begin
  require 'chronic'
  $have_chronic = true
rescue LoadError => e
  debug "optional 'chronic' library not found; date-time query restrictions disabled"
  $have_chronic = false
end

module Redwood
module Server

class BaseIndex
  def initialize dir=BASE_DIR
    @dir = dir
    @sync_worker = nil
    @sync_queue = Queue.new
  end

  def load
    load_index
  end

  def save
    debug "saving index and sources..."
    FileUtils.mkdir_p @dir unless File.exists? @dir
    save_index
  end

  def load_index
    unimplemented
  end

  def add_message m; unimplemented end
  def update_message m; unimplemented end
  def update_message_state m; unimplemented end

  def save_index fn
    unimplemented
  end

  def contains_id? id
    unimplemented
  end

  def contains? m; contains_id? m.id end

  def size
    unimplemented
  end

  def empty?; size == 0 end

  ## Yields a message-id and message-building lambda for each
  ## message that matches the given query, in descending date order.
  ## You should probably not call this on a block that doesn't break
  ## rather quickly because the results can be very large.
  def each_id_by_date query={}
    unimplemented
  end

  ## Return the number of matches for query in the index
  def num_results_for query={}
    unimplemented
  end

  ## yield all messages in the thread containing 'm' by repeatedly
  ## querying the index. yields pairs of message ids and
  ## message-building lambdas, so that building an unwanted message
  ## can be skipped in the block if desired.
  ##
  ## only two options, :limit and :skip_killed. if :skip_killed is
  ## true, stops loading any thread if a message with a :killed flag
  ## is found.
  def each_message_in_thread_for m, opts={}
    unimplemented
  end

  ## Load message with the given message-id from the index
  def build_message id
    unimplemented
  end

  ## Delete message with the given message-id from the index
  def delete id
    unimplemented
  end

  ## Given an array of email addresses, return an array of Person objects that
  ## have sent mail to or received mail from any of the given addresses.
  def load_contacts email_addresses, h={}
    unimplemented
  end

  ## Yield each message-id matching query
  def each_id query={}
    unimplemented
  end

  ## Yield each message matching query
  def each_message query={}, &b
    each_id query do |id|
      yield build_message(id)
    end
  end

  ## Implementation-specific optimization step
  def optimize
    unimplemented
  end

  ## Return the id source of the source the message with the given message-id
  ## was synced from
  def source_for_id id
    unimplemented
  end

  class ParseError < StandardError; end

  ## parse a query string from the user. returns a query object
  ## that can be passed to any index method with a 'query'
  ## argument.
  ##
  ## raises a ParseError if something went wrong.
  def parse_query s
    unimplemented
  end

  def save_thread t
    t.each_dirty_message do |m|
      if @sync_worker
        @sync_queue << m
      else
        update_message_state m
      end
      m.clear_dirty
    end
  end

  def start_sync_worker
    @sync_worker = Redwood::reporting_thread('index sync') { run_sync_worker }
  end

  def stop_sync_worker
    return unless worker = @sync_worker
    @sync_worker = nil
    @sync_queue << :die
    worker.join
  end

  def run_sync_worker
    while m = @sync_queue.deq
      return if m == :die
      update_message_state m
      # Necessary to keep Xapian calls from lagging the UI too much.
      sleep 0.03
    end
  end
end

end
end
