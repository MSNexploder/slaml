module Haml
  # Tilt template implementation for Slaml
  # @api public
  Template = Temple::Templates::Tilt(Slaml::Engine, :register_as => :haml)

  if defined?(::ActionView)
    # Rails template implementation for Slaml
    # @api public
    RailsTemplate = Temple::Templates::Rails(Slaml::Engine,
                                             :register_as => :haml,
                                             # Use rails-specific generator. This is necessary
                                             # to support block capturing and streaming.
                                             :generator => Temple::Generators::RailsOutputBuffer,
                                             # Disable the internal slaml capturing.
                                             # Rails takes care of the capturing by itself.
                                             :disable_capture => true,
                                             :streaming => defined?(::Fiber))
  end
end
