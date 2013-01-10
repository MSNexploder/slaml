module Slaml
  # Tilt template implementation for Slaml
  # @api public
  Template = Temple::Templates::Tilt(Slaml::Engine, :register_as => :slaml)
end
