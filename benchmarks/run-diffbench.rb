#!/usr/bin/env ruby

$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'), File.dirname(__FILE__))

require 'slaml'
require 'context'
require 'diffbench'

content = File.read(File.dirname(__FILE__) + '/view.haml')
engine = Slaml::Engine.new
template = Slaml::Template.new { content }
context = Context.new

DiffBench.bm do
  report("Parse") do
    2000.times { engine.call(content) }
  end
  report("Render") do
    100000.times { template.render(context) }
  end
end
