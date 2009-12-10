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
    while not @die
      Actor.receive do |f|
        yield f
        f.when(:die) { @die = true }
        f.when(Object) { |o| fail "unexpected message #{o.inspect}" }
      end
    end
  end

  def ensure
  end
end

class Actor::Mailbox::Filter
  def ignore x
    self.when(x) {}
  end
end
