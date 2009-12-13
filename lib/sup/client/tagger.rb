# encoding: utf-8
module Redwood

class Tagger
  def initialize mode, noun="thread", plural_noun=nil
    @mode = mode
    @tagged = {}
    @noun = noun
    @plural_noun = plural_noun || (@noun + "s")
  end

  def tagged? o; @tagged[o]; end
  def toggle_tag_for o; @tagged[o] = !@tagged[o]; end
  def tag o; @tagged[o] = true; end
  def untag o; @tagged[o] = false; end
  def drop_all_tags; @tagged.clear; end
  def drop_tag_for o; @tagged.delete o; end

  def apply_to_tagged action=nil
    targets = @tagged.select_by_value
    num_tagged = targets.size
    if num_tagged == 0
      $buffers.flash "No tagged threads!"
      return
    end

    noun = num_tagged == 1 ? @noun : @plural_noun

    unless action
      c = $buffers.ask_getch "apply to #{num_tagged} tagged #{noun}:"
      return if c.nil? # user cancelled
      action = @mode.resolve_input c
    end

    if action
      tagged_sym = "multi_#{action}".intern
      if @mode.respond_to? tagged_sym
        @mode.send tagged_sym, targets
      else
        $buffers.flash "That command cannot be applied to multiple threads."
      end
    else
      $buffers.flash "Unknown command #{c.to_character}."
    end
  end

end

end
