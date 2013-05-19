#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'), File.dirname(__FILE__))

require 'slaml'

content = File.read(File.dirname(__FILE__) + '/view.haml')
engine = Slaml::Engine.new

1000.times { engine.call(content) }
