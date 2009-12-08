# encoding: utf-8
require 'revactor'
require 'iconv'
require 'thread'
require 'yaml'
require 'monitor'
require 'rmail'

DEBUG_ENCODING = true
$encoding = "UTF-8"

module Redwood; end

module Redwood::Server
  VERSION = "git"

  BASE_DIR   = ENV["SUP_SERVER_BASE"] || File.join(ENV["HOME"], ".sup-server")
  CONFIG_FN  = File.join(BASE_DIR, "config.yaml")
  LOCK_FN    = File.join(BASE_DIR, "lock")
  SUICIDE_FN = File.join(BASE_DIR, "please-kill-yourself")
  HOOK_DIR   = File.join(BASE_DIR, "hooks")

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
require 'sup/protocol'
require 'sup/message'
require 'sup/message-chunks'
require 'sup/person'
require 'sup/protocol'
require 'sup/rfc2047'
require 'sup/thread'
require 'sup/interactive-lock'
require 'sup/server/storage'
require 'sup/server/index'
require 'sup/server/xapian_index'
require 'sup/server/requests'
require 'sup/server/server'
