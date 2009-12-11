#!/usr/bin/env rackup
#\ -w -p 8765
use Rack::Reloader, 0
use Rack::ContentLength
require 'web'
run Redwood::Web.new('unix:/tmp/sup')
