# encoding: utf-8
require 'rubygems'
require 'yaml'
require 'zlib'
require 'thread'
require 'fileutils'
require 'gettext'
require 'curses'
require 'bert'

module Redwood::Client
  BASE_DIR   = ENV["SUP_BASE"] || File.join(ENV["HOME"], ".sup")
  CONFIG_FN  = File.join(BASE_DIR, "config.yaml")
  COLOR_FN   = File.join(BASE_DIR, "colors.yaml")
  SOURCE_FN  = File.join(BASE_DIR, "sources.yaml")
  LABEL_FN   = File.join(BASE_DIR, "labels.txt")
  CONTACT_FN = File.join(BASE_DIR, "contacts.txt")
  DRAFT_DIR  = File.join(BASE_DIR, "drafts")
  SENT_FN    = File.join(BASE_DIR, "sent.mbox")
  LOCK_FN    = File.join(BASE_DIR, "lock")
  SUICIDE_FN = File.join(BASE_DIR, "please-kill-yourself")
  HOOK_DIR   = File.join(BASE_DIR, "hooks")

  def start
    Redwood::SentManager.init $config[:sent_source] || 'sup://sent'
    Redwood::ContactManager.init Redwood::CONTACT_FN
    Redwood::LabelManager.init Redwood::LABEL_FN
    Redwood::AccountManager.init $config[:accounts]
    Redwood::DraftManager.init Redwood::DRAFT_DIR
    Redwood::UpdateManager.init
    Redwood::PollManager.init
    Redwood::CryptoManager.init
    Redwood::UndoManager.init
    Redwood::SourceManager.init
  end

  def finish
    Redwood::LabelManager.save if Redwood::LabelManager.instantiated?
    Redwood::ContactManager.save if Redwood::ContactManager.instantiated?
    Redwood::BufferManager.deinstantiate! if Redwood::BufferManager.instantiated?
  end

  ## not really a good place for this, so I'll just dump it here.
  ##
  ## a source error is either a FatalSourceError or an OutOfSyncSourceError.
  ## the superclass SourceError is just a generic.
  def report_broken_sources opts={}
    return unless BufferManager.instantiated?

    broken_sources = SourceManager.sources.select { |s| s.error.is_a? FatalSourceError }
    unless broken_sources.empty?
      BufferManager.spawn_unless_exists("Broken source notification for #{broken_sources.join(',')}", opts) do
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

    desynced_sources = SourceManager.sources.select { |s| s.error.is_a? OutOfSyncSourceError }
    unless desynced_sources.empty?
      BufferManager.spawn_unless_exists("Out-of-sync source notification for #{broken_sources.join(',')}", opts) do
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

  module_function :start, :finish, :report_broken_sources
end

=begin

require "sup/util"
require "sup/hook"

## we have to initialize this guy first, because other classes must
## reference it in order to register hooks, and they do that at parse
## time.
Redwood::HookManager.init Redwood::HOOK_DIR

## everything we need to get logging working
require "sup/logger"
Redwood::Logger.init.add_sink $stderr
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
require "sup/buffer"
require "sup/keymap"
require "sup/mode"
require "sup/modes/scroll-mode"
require "sup/modes/text-mode"
require "sup/modes/log-mode"
require "sup/update"
require "sup/message-chunks"
require "sup/message"
require "sup/source"
require "sup/mbox"
require "sup/maildir"
require "sup/imap"
require "sup/person"
require "sup/account"
require "sup/thread"
require "sup/interactive-lock"
require "sup/index"
require "sup/textfield"
require "sup/colormap"
require "sup/label"
require "sup/contact"
require "sup/tagger"
require "sup/draft"
require "sup/poll"
require "sup/crypto"
require "sup/undo"
require "sup/horizontal-selector"
require "sup/modes/line-cursor-mode"
require "sup/modes/help-mode"
require "sup/modes/edit-message-mode"
require "sup/modes/compose-mode"
require "sup/modes/resume-mode"
require "sup/modes/forward-mode"
require "sup/modes/reply-mode"
require "sup/modes/label-list-mode"
require "sup/modes/contact-list-mode"
require "sup/modes/thread-view-mode"
require "sup/modes/thread-index-mode"
require "sup/modes/label-search-results-mode"
require "sup/modes/search-results-mode"
require "sup/modes/person-search-results-mode"
require "sup/modes/inbox-mode"
require "sup/modes/buffer-list-mode"
require "sup/modes/poll-mode"
require "sup/modes/file-browser-mode"
require "sup/modes/completion-mode"
require "sup/modes/console-mode"
require "sup/sent"

$:.each do |base|
  d = File.join base, "sup/share/modes/"
  Redwood::Mode.load_all_modes d if File.directory? d
end
=end
