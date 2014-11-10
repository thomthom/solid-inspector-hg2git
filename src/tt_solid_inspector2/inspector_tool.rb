#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------


module TT::Plugins::SolidInspector2

  require File.join(PATH, "error_finder.rb")
  require File.join(PATH, "instance.rb")


  class InspectorTool

    def initialize
      puts "InspectorTool.initialize"
      @errors = []
      @current_error = 0
      @groups = []

      model = Sketchup.active_model
      entities = model.active_entities
      instance_path = model.active_path || []
      transformation = Geom::Transformation.new

      unless model.selection.empty?
        puts "> Selection:"
        instance = Sketchup.active_model.selection.find { |entity|
          Instance.is?(entity)
        }
        puts "  > Instance: #{instance.inspect}"
        if instance
          definition = Instance.definition(instance)
          entities = definition.entities
          instance_path << instance
          transformation = instance.transformation
        end
      end

      puts "> Entities: #{entities}"
      puts "> Instance Path: #{instance_path.inspect}"
      puts "> Transformation: #{transformation.to_a}"
      analyze(entities, instance_path, transformation)
    end

    def activate
      Sketchup.active_model.active_view.invalidate
      update_ui
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      view.invalidate
      update_ui
    end

    def onLButtonUp(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      if Instance.is?(ph.best_picked)
        analyze(ph.best_picked)
      end
      view.invalidate
    end

    def onKeyUp(key, repeat, flags, view)
      return if @groups.empty?

      shift = flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK

      # Iterate over the error found using Tab, Up/Down, Left/Right.
      # Tab will zoom to the current error.

      if key == 9 # Tab
        if shift
          @current_error = (@current_error - 1) % @groups.length
        else
          @current_error = (@current_error + 1) % @groups.length
        end
      end

      if key == VK_UP || key == VK_RIGHT
        @current_error = (@current_error + 1) % @groups.length
      end

      if key == VK_DOWN || key == VK_LEFT
        @current_error = (@current_error - 1) % @groups.length
      end

      if key == 13 || key == 9
        zoom_to_error(view)
      end

      view.invalidate
    end

    def draw(view)
      @errors.each { |error|
        error.draw(view, @transformation)
      }
      nil
    end

    private

    def analyze(entities, instance_path, transformation)
      puts "analyse"
      @errors = ErrorFinder.find_errors(entities)
      puts "> Errors: #{@errors.size}"
      puts @errors.join("\n")
      @entities = entities
      @instance_path = instance_path
      @transformation = transformation
      nil
    end

    def update_ui
      message = "Click on solids to inspect. Use arrow keys to cycle between "\
        "errors. Press Return to zoom to error. Press Tab/Shift+Tab to cycle "\
        "though errors and zoom."
      Sketchup.status_text = message
      nil
    end

    def zoom_to_error(view)
      entities = @groups[ @current_error ]
      view.zoom(entities)
      # Adjust camera for the instance transformation
      camera = view.camera
      tr = @transformation
      eye = camera.eye.transform(tr)
      target = camera.target.transform(tr)
      up = camera.up.transform(tr)
      view.camera.set(eye, target, up)
      nil
    end

  end # class InspectorTool
end # module TT::Plugins::SolidInspector2