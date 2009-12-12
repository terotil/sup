require 'sup/util/yaml_config'

module Redwood
module Client

module Config

YC = Redwood::Util::YAMLConfig

def load fn
  ## set up default configuration file
  if File.exists? fn
    $config = YC.load_yaml_obj fn
    abort "#{fn} is not a valid configuration file (it's a #{$config.class}, not a hash)" unless $config.is_a?(Hash)
  else
    require 'etc'
    require 'socket'
    name = Etc.getpwnam(ENV["USER"]).gecos.split(/,/).first rescue nil
    name ||= ENV["USER"]
    email = ENV["USER"] + "@" + 
      begin
        Socket.gethostbyname(Socket.gethostname).first
      rescue SocketError
        Socket.gethostname
      end

    $config = {
      :accounts => {
        :default => {
          :name => name,
          :email => email,
          :alternates => [],
          :sendmail => "/usr/sbin/sendmail -oem -ti",
          :signature => File.join(ENV["HOME"], ".signature")
        }
      },
      :editor => ENV["EDITOR"] || "/usr/bin/vim -f -c 'setlocal spell spelllang=en_us' -c 'set filetype=mail'",
      :thread_by_subject => false,
      :edit_signature => false,
      :ask_for_to => true,
      :ask_for_cc => true,
      :ask_for_bcc => false,
      :ask_for_subject => true,
      :confirm_no_attachments => true,
      :confirm_top_posting => true,
      :discard_snippets_from_encrypted_messages => false,
      :default_attachment_save_dir => "",
      :sent_source => "sup://sent"
    }
    begin
      FileUtils.mkdir_p File.dirname(fn)
      YC.save_yaml_obj $config, fn
    rescue StandardError => e
      $stderr.puts "warning: #{e.message}"
    end
  end

end

end
end
