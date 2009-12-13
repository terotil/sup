# encoding: utf-8
require 'sup/util/yaml_config'

module Redwood::Server

YC = Redwood::Util::YAMLConfig

module Config
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
        :discard_snippets_from_encrypted_messages => false,
      }
      begin
        FileUtils.mkdir_p File.dirname(fn)
        YC.save_yaml_obj $config, fn
      rescue StandardError => e
        $stderr.puts "warning: #{e.message}"
      end
    end
  end

  module_function :load
end

end
