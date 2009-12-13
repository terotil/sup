# encoding: utf-8
module Redwood
module Client

class ComposeMode < EditMessageMode
  def initialize opts={}
    header = {}
    header["From"] = (opts[:from] || $accounts.default_account).full_address
    header["To"] = opts[:to].map { |p| p.full_address }.join(", ") if opts[:to]
    header["Cc"] = opts[:cc].map { |p| p.full_address }.join(", ") if opts[:cc]
    header["Bcc"] = opts[:bcc].map { |p| p.full_address }.join(", ") if opts[:bcc]
    header["Subject"] = opts[:subj] if opts[:subj]
    header["References"] = opts[:refs].map { |r| "<#{r}>" }.join(" ") if opts[:refs]
    header["In-Reply-To"] = opts[:replytos].map { |r| "<#{r}>" }.join(" ") if opts[:replytos]

    super :header => header, :body => (opts[:body] || [])
  end

  def edit_message
    edited = super
    $buffers.kill_buffer self.buffer unless edited
    edited
  end

  def self.spawn_nicely opts={}
    to = opts[:to] || ($buffers.ask_for_contacts(:people, "To: ", [opts[:to_default]]) or return if ($config[:ask_for_to] != false))
    cc = opts[:cc] || ($buffers.ask_for_contacts(:people, "Cc: ") or return if $config[:ask_for_cc])
    bcc = opts[:bcc] || ($buffers.ask_for_contacts(:people, "Bcc: ") or return if $config[:ask_for_bcc])
    subj = opts[:subj] || ($buffers.ask(:subject, "Subject: ") or return if $config[:ask_for_subject])
    
    mode = ComposeMode.new :from => opts[:from], :to => to, :cc => cc, :bcc => bcc, :subj => subj
    $buffers.spawn "New Message", mode
    mode.edit_message
  end
end

end
end
