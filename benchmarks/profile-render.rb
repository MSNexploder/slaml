#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'), File.dirname(__FILE__))

require 'slaml'
require 'context'

content = File.read(File.dirname(__FILE__) + '/view.haml')
slaml = Slaml::Template.new { content }
context = Context.new

10000.times { slaml.render(context) }
