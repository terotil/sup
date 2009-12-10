# encoding: utf-8
require 'revactor'
require 'thread'
require 'yaml'
require 'monitor'
require 'rmail'

require 'sup'

module Redwood::Server
  BASE_DIR   = ENV["SUP_SERVER_BASE"] || File.join(ENV["HOME"], ".sup-server")
  CONFIG_FN  = File.join(BASE_DIR, "config.yaml")
  LOCK_FN    = File.join(BASE_DIR, "lock")
  SUICIDE_FN = File.join(BASE_DIR, "please-kill-yourself")
  HOOK_DIR   = File.join(BASE_DIR, "hooks")
  STORAGE_FN  = File.join(BASE_DIR, "storage")
  INDEX_FN  = File.join(BASE_DIR, "index")

  YAML_DOMAIN = "masanjin.net"
  YAML_DATE = "2006-10-01"
end

require 'sup/util'
require 'sup/server/config'
require 'sup/hook'

Redwood::Server::Config.load
Redwood::HookManager.init Redwood::Server::HOOK_DIR

require 'sup/logger'
Redwood::Logger.init.add_sink $stderr
include Redwood::LogsStuff

require 'sup/crypto'

Redwood::CryptoManager.init

require 'sup/protocol'
require 'sup/message'
require 'sup/message-chunks'
require 'sup/person'
require 'sup/protocol'
require 'sup/rfc2047'
require 'sup/thread'
require 'sup/server/index-lock'
require 'sup/server/storage'
require 'sup/server/storage-actor'
require 'sup/server/index'
require 'sup/server/index-actor'
require 'sup/server/requests'
require 'sup/server/dispatcher'

begin
  require 'chronic'
  $have_chronic = true
rescue LoadError => e
  debug "optional 'chronic' library not found; date-time query restrictions disabled"
  $have_chronic = false
end
