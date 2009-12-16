# encoding: utf-8
require 'rubygems'
require 'yaml'
require 'zlib'
require 'thread'
require 'fileutils'
require 'gettext'
require 'curses'
require 'bert'
require 'sup/util'

module Redwood::Client
  BASE_DIR   = ENV["SUP_BASE"] || File.join(ENV["HOME"], ".sup")
  CONFIG_FN  = File.join(BASE_DIR, "config.yaml")
  COLOR_FN   = File.join(BASE_DIR, "colors.yaml")
  SOURCE_FN  = File.join(BASE_DIR, "sources.yaml")
  CONTACT_FN = File.join(BASE_DIR, "contacts.txt")
  LABELS_FN  = File.join(BASE_DIR, "labels.txt")
  HOOK_DIR   = File.join(BASE_DIR, "hooks")
  LOCK_FN    = File.join(BASE_DIR, "lock")
  SUICIDE_FN = File.join(BASE_DIR, "please-kill-yourself")

  def start
    Dir.mkdir BASE_DIR unless File.exists? BASE_DIR
    $sources = Redwood::SourceManager.new SOURCE_FN
    $sources.load_sources
    $config = Redwood::Client::Config.load CONFIG_FN
    $contacts = Redwood::Client::ContactManager.new CONTACT_FN
    $labels = Redwood::Client::LabelManager.new LABELS_FN
    $accounts = Redwood::Client::AccountManager.new $config[:accounts]
    $crypto = Redwood::CryptoManager.new
    $undo = Redwood::Client::UndoManager.new
  end

  def finish
    $contacts.save if $contacts
    $sources.save_sources if $sources
  end

  ## not really a good place for this, so I'll just dump it here.
  ##
  ## a source error is either a FatalSourceError or an OutOfSyncSourceError.
  ## the superclass SourceError is just a generic.
  def report_broken_sources opts={}
    return unless $buffers

    broken_sources = $sources.sources.select { |s| s.error.is_a? FatalSourceError }
    unless broken_sources.empty?
      $buffers.spawn_unless_exists("Broken source notification for #{broken_sources.join(',')}", opts) do
        TextMode.new(<<EOM)
Source error notification
-------------------------

Hi there. It looks like one or more message sources is reporting
errors. Until this is corrected, messages from these sources cannot
be viewed, and new messages will not be detected.

#{broken_sources.map { |s| "Source: " + s.to_s + "\n Error: " + s.error.message.wrap(70).join("\n        ")}.join("\n\n")}
EOM
#' stupid ruby-mode
      end
    end

    desynced_sources = $sources.sources.select { |s| s.error.is_a? OutOfSyncSourceError }
    unless desynced_sources.empty?
      $buffers.spawn_unless_exists("Out-of-sync source notification for #{broken_sources.join(',')}", opts) do
        TextMode.new(<<EOM)
Out-of-sync source notification
-------------------------------

Hi there. It looks like one or more sources has fallen out of sync
with my index. This can happen when you modify these sources with
other email clients. (Sorry, I don't play well with others.)

Until this is corrected, messages from these sources cannot be viewed,
and new messages will not be detected. Luckily, this is easy to correct!

#{desynced_sources.map do |s|
  "Source: " + s.to_s + 
   "\n Error: " + s.error.message.wrap(70).join("\n        ") + 
   "\n   Fix: sup-sync --changed #{s.to_s}"
  end}
EOM
#' stupid ruby-mode
      end
    end
  end

  ## record exceptions thrown in threads nicely
  @exceptions = []
  @exception_mutex = Mutex.new

  attr_reader :exceptions
  def record_exception e, name
    @exception_mutex.synchronize do
      @exceptions ||= []
      @exceptions << [e, name]
    end
  end

  module_function :start, :finish, :report_broken_sources, :exceptions, :record_exception
end

require "sup/util"
require "sup/hook"

## we have to initialize this guy first, because other classes must
## reference it in order to register hooks, and they do that at parse
## time.
$hooks = Redwood::HookManager.new Redwood::Client::HOOK_DIR

## everything we need to get logging working
require "sup/logger"
$logger = Redwood::Logger.new
$logger.add_sink $stderr
include Redwood::LogsStuff

## determine encoding and character set
$encoding = Locale.current.charset
if $encoding
  debug "using character set encoding #{$encoding.inspect}"
else
  warn "can't find character set by using locale, defaulting to utf-8"
  $encoding = "UTF-8"
end

require 'sup/protocol'
require "sup/client/buffer"
require "sup/client/keymap"
require "sup/client/mode"
require "sup/client/modes/scroll-mode"
require "sup/client/modes/text-mode"
require "sup/client/modes/log-mode"
require "sup/client/update"
require "sup/client/config"
require "sup/message-chunks"
require "sup/message"
require "sup/source"
require "sup/source/mbox"
require "sup/source/maildir"
require "sup/source/imap"
require "sup/person"
require "sup/client/account"
require "sup/thread"
require "sup/client/textfield"
require "sup/client/colormap"
require "sup/client/label"
require "sup/client/contact"
require "sup/client/tagger"
require "sup/client/poll"
require "sup/crypto"
require 'sup/query'
require 'sup/queryparser'
require "sup/client/undo"
require "sup/client/horizontal-selector"
require "sup/client/modes/line-cursor-mode"
require "sup/client/modes/help-mode"
require "sup/client/modes/edit-message-mode"
require "sup/client/modes/compose-mode"
require "sup/client/modes/resume-mode"
require "sup/client/modes/forward-mode"
require "sup/client/modes/reply-mode"
require "sup/client/modes/label-list-mode"
require "sup/client/modes/contact-list-mode"
require "sup/client/modes/thread-view-mode"
require "sup/client/modes/thread-index-mode"
require "sup/client/modes/label-search-results-mode"
require "sup/client/modes/search-results-mode"
require "sup/client/modes/person-search-results-mode"
require "sup/client/modes/inbox-mode"
require "sup/client/modes/buffer-list-mode"
require "sup/client/modes/poll-mode"
require "sup/client/modes/file-browser-mode"
require "sup/client/modes/completion-mode"
require "sup/client/modes/console-mode"

$:.each do |base|
  d = File.join base, "sup/share/modes/"
  Redwood::Mode.load_all_modes d if File.directory? d
end
