require 'revactor'

class Actorized
  extend Actorize

  def initialize *a
    #fail unless h.is_a? Hash
    #h.each { |k,v| self[k] = v }
    @die = false
    begin
      run *a
    ensure
      self.send :ensure
    end
  end

  def kill
    self << :die
  end

  def [](k)
    me[k]
  end

private

  def []=(k,v)
    me[k] = v
  end

  def me
    Actor.current
  end

  def msgloop
    catch :die do
      loop do
        Actor.receive do |f|
          yield f
        end
      end
    end
  end

  def main_msgloop
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
    self.when(x) { raise "unexpected message #{x.inspect}" }
  end

  def die? x=:die
    self.when(x) { throw(:die) }
  end
end
