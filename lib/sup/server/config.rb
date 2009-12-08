module Redwood::Config
	def load
		## set up default configuration file
		if File.exists? Redwood::CONFIG_FN
			$config = load_yaml_obj Redwood::CONFIG_FN
			abort "#{Redwood::CONFIG_FN} is not a valid configuration file (it's a #{$config.class}, not a hash)" unless $config.is_a?(Hash)
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
				FileUtils.mkdir_p Redwood::BASE_DIR
				save_yaml_obj $config, Redwood::CONFIG_FN
			rescue StandardError => e
				$stderr.puts "warning: #{e.message}"
			end
		end
	end

## one-stop shop for yamliciousness
  def save_yaml_obj o, fn, safe=false
    o = if o.is_a?(Array)
      o.map { |x| (x.respond_to?(:before_marshal) && x.before_marshal) || x }
    elsif o.respond_to? :before_marshal
      o.before_marshal
    else
      o
    end

    if safe
      safe_fn = "#{File.dirname fn}/safe_#{File.basename fn}"
      mode = File.stat(fn).mode if File.exists? fn
      File.open(safe_fn, "w", mode) { |f| f.puts o.to_yaml }
      FileUtils.mv safe_fn, fn
    else
      File.open(fn, "w") { |f| f.puts o.to_yaml }
    end
  end

  def load_yaml_obj fn, compress=false
    o = if File.exists? fn
      if compress
        Zlib::GzipReader.open(fn) { |f| YAML::load f }
      else
        YAML::load_file fn
      end
    end
    if o.is_a?(Array)
      o.each { |x| x.after_unmarshal! if x.respond_to?(:after_unmarshal!) }
    else
      o.after_unmarshal! if o.respond_to?(:after_unmarshal!)
    end
    o
  end

  module_function :save_yaml_obj, :load_yaml_obj, :load
end
