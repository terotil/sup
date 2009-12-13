# encoding: utf-8
module Redwood
module Client

class TextMode < ScrollMode
  attr_reader :text
  register_keymap do |k|
    k.add :save_to_disk, "Save to disk", 's'
    k.add :pipe, "Pipe to process", '|'
  end

  def initialize text="", filename=nil
    @text = text
    @filename = filename
    update_lines
    buffer.mark_dirty if buffer
    super()
  end

  def save_to_disk
    fn = $buffers.ask_for_filename :filename, "Save to file: ", @filename
    save_to_file(fn) { |f| f.puts text } if fn
  end

  def pipe
    command = $buffers.ask(:shell, "pipe command: ")
    return if command.nil? || command.empty?

    output = pipe_to_process(command) do |stream|
      @text.each { |l| stream.puts l }
    end

    if output
      $buffers.spawn "Output of '#{command}'", TextMode.new(output)
    else
      $buffers.flash "'#{command}' done!"
    end
  end

  def text= t
    @text = t
    update_lines
    if buffer
      ensure_mode_validity
      buffer.mark_dirty 
    end
  end

  def << line
    @lines = [0] if @text.empty?
    @text << line
    @lines << @text.length
    if buffer
      ensure_mode_validity
      buffer.mark_dirty
    end
  end

  def lines
    @lines.length - 1
  end

  def [] i
    return nil unless i < @lines.length
    @text[@lines[i] ... (i + 1 < @lines.length ? @lines[i + 1] - 1 : @text.length)].normalize_whitespace
#    (@lines[i] ... (i + 1 < @lines.length ? @lines[i + 1] - 1 : @text.length)).inspect
  end

private

  def update_lines
    pos = @text.find_all_positions("\n")
    pos.push @text.length unless pos.last == @text.length - 1
    @lines = [0] + pos.map { |x| x + 1 }
  end
end

end
end
