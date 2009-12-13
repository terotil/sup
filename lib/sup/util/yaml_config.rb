# encoding: utf-8

module Redwood
module Util

module YAMLConfig

## one-stop shop for yamliciousness
  def save_yaml_obj o, fn, safe=false
    o = if o.is_a?(Array)
      o.map { |x| (x.respond_to?(:before_marshal) && x.before_marshal) || x }
    elsif o.respond_to? :before_marshal
      o.before_marshal
    else
      o
    end

    FileUtils.mkdir_p File.dirname(fn)
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

  module_function :save_yaml_obj, :load_yaml_obj
end

end
end
