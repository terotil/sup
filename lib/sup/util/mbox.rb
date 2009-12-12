# encoding: utf-8
require 'time'

module Redwood
module Util

module MBox
  BREAK_RE = /^From \S+ (.+)[\n]$/

  def is_break_line? l
    l =~ BREAK_RE or return false
    time = $1
    begin
      ## hack -- make Time.parse fail when trying to substitute values from Time.now
      Time.parse time, 0
      true
    rescue NoMethodError, ArgumentError
      warn "found invalid date in potential mbox split line, not splitting: #{l.inspect}"
      false
    end
  end
  module_function :is_break_line?
end

end
end
