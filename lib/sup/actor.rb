require 'revactor'

class Actorized
  extend Actorize
  attr_reader :me

  def initialize *a
    #fail unless h.is_a? Hash
    #h.each { |k,v| self[k] = v }
    @me = Actor.current
    @die = false
    begin
      debug "#{to_s} spawned"
      run *a
    ensure
      self.send :ensure
      debug "#{to_s} dying"
    end
  end

  def to_s
    self.class.name
  end

  def kill
    self << :die
  end

  def [](k)
    me[k]
  end

  def msgloop &b; self.class.msgloop &b; end
  def main_msgloop &b; self.class.main_msgloop &b; end

private

  def []=(k,v)
    me[k] = v
  end

  def self.msgloop
    catch :die do
      loop do
        Actor.receive do |f|
          yield f
        end
      end
    end
  end

  def self.main_msgloop
    msgloop do |f|
      yield f
      f.die?
      f.unexpected
    end
  end

  def expect x
    ret = nil
    Actor.receive do |f|
      f.when(x) { |y| ret = yield(*y) if block_given? }
    end
    ret
  end

  def ensure
  end

  def _2; lambda { |_,x| x }; end
end

class Actor::Mailbox::Filter
  def ignore x
    self.when(x) {}
  end

  def unexpected x=Object
    self.when(x) { |y| raise "unexpected message #{y.inspect}" }
  end

  def die? x=:die
    self.when(x) { throw(:die) }
  end
end
