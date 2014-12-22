#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require "set"


module TT::Plugins::SolidInspector2

  require File.join(PATH, "error_finder.rb")
  require File.join(PATH, "inspector_window.rb")
  require File.join(PATH, "instance.rb")
  require File.join(PATH, "key_codes.rb")


  class InspectorTool

    include KeyCodes


    def initialize
      @errors = []
      @current_error = 0
      @filtered_errors = nil

      @entities = nil
      @instance_path = nil
      @transformation = nil

      @window = nil
      @deactivating = false
      nil
    end


    def activate
      @deactivating = false

      @window ||= create_window
      @window.show

      Sketchup.active_model.active_view.invalidate
      update_ui
      nil
    end


    def deactivate(view)
      if @window && @window.visible?
        @deactivating = true
        @window.close
      end
      view.invalidate
      nil
    end


    def resume(view)
      view.invalidate
      update_ui
      nil
    end


    def onLButtonUp(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      view.model.selection.clear
      if Instance.is?(ph.best_picked)
        view.model.selection.add(ph.best_picked)
      end
      analyze
      view.invalidate
      nil
    end


    def onKeyUp(key, repeat, flags, view)
      return if @errors.empty?

      shift = flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK

      # Iterate over the error found using Tab, Up/Down, Left/Right.
      # Tab will zoom to the current error.
      errors = filtered_errors

      if key == KEY_TAB
        if shift
          @current_error = (@current_error - 1) % errors.size
        else
          @current_error = (@current_error + 1) % errors.size
        end
      end

      if key == VK_UP || key == VK_RIGHT
        @current_error = (@current_error + 1) % errors.size
      end

      if key == VK_DOWN || key == VK_LEFT
        @current_error = (@current_error - 1) % errors.size
      end

      if key == KEY_RETURN || key == KEY_TAB
        zoom_to_error(view)
      end

      if key == KEY_ESCAPE
        deselect_tool
        #return true
      end

      view.invalidate
      false # Returning true would cancel the key event.
    end


    def draw(view)
      filtered_errors.each { |error|
        error.draw(view, @transformation)
        if error.is_a?(SolidErrors::ShortEdge)
          draw_short_edge_error(error, view)
        end
      }
      nil
    end


    private


    def analyze
      #puts "analyse"

      model = Sketchup.active_model
      entities = model.active_entities
      instance_path = model.active_path || []
      transformation = Geom::Transformation.new

      unless model.selection.empty?
        #puts "> Selection:"
        instance = Sketchup.active_model.selection.find { |entity|
          Instance.is?(entity)
        }
        #puts "  > Instance: #{instance.inspect}"
        if instance
          definition = Instance.definition(instance)
          entities = definition.entities
          instance_path << instance
          transformation = instance.transformation
        end
      end

      #puts "> Entities: #{entities}"
      #puts "> Instance Path: #{instance_path.inspect}"
      #puts "> Transformation: #{transformation.to_a}"

      @filtered_errors = nil
      @current_error = 0
      @errors = ErrorFinder.find_errors(entities, transformation)
      @entities = entities
      @instance_path = instance_path
      @transformation = transformation

      # Push results to webdialog.
      grouped_errors = group_errors(@errors)
      #puts JSON.pretty_generate(grouped_errors)
      @window.call("list_errors", grouped_errors)
      update_ui
      nil
    end


    def deselect_tool
      Sketchup.active_model.select_tool(nil)
    end


    def create_window
      window = InspectorWindow.new
      window.set_on_close {
        unless @deactivating
          Sketchup.active_model.select_tool(nil)
        end
      }
      window.on("html_ready") { |dialog|
        analyze
        Sketchup.active_model.active_view.invalidate
      }
      window.on("fix_all") { |dialog|
        fix_all
        Sketchup.active_model.active_view.invalidate
      }
      window.on("fix_group") { |dialog, data|
        fix_group(data["type"])
        Sketchup.active_model.active_view.invalidate
      }
      window.on("select_group") { |dialog, data|
        select_group(data[0])
        Sketchup.active_model.active_view.invalidate
      }
      window.on("keydown") { |dialog, data|
        forward_key(:onKeyDown, data)
      }
      window.on("keyup") { |dialog, data|
        forward_key(:onKeyUp, data)
      }
      window
    end


    def forward_key(method, jquery_event)
      key = jquery_event["key"]
      repeat = false
      flags = 0
      view = Sketchup.active_model.active_view
      #p [method, key]
      send(method, key, repeat, flags, view)
      nil
    end


    def filtered_errors
      if @filtered_errors.nil?
        errors = @errors
      else
        errors = @errors.grep(@filtered_errors)
      end
      errors
    end


    def fix_all
      all_errors_fixed = ErrorFinder.fix_errors(@errors, @entities)
      process_fix_all_results(all_errors_fixed)
      analyze
    end


    def fix_group(type)
      error_klass = SolidErrors.const_get(type)
      errors = @errors.select { |error|
        error.is_a?(error_klass)
      }
      all_errors_fixed = ErrorFinder.fix_errors(errors, @entities)
      process_fix_results(all_errors_fixed, error_klass)
      analyze
    end


    def process_fix_results(all_errors_fixed, error_klass)
      unless all_errors_fixed
        UI.messagebox(error_klass.description)
      end
      nil
    end


    def process_fix_all_results(all_errors_fixed)
      unless all_errors_fixed
        message = "Some errors could not be automatically fixed. "\
          "Manually inspect and correct the errors, then run the tool again."
        UI.messagebox(message)
      end
      nil
    end


    def select_group(type)
      if type.nil?
        @filtered_errors = nil
      else
        klass = SolidErrors.const_get(type)
        @filtered_errors = klass
      end
      @current_error = 0
      nil
    end


    def group_errors(errors)
      groups = {}
      errors.each { |error|
        unless groups.key?(error.class)
          groups[error.class] = {
            :type        => error.class.type_name,
            :name        => error.class.display_name,
            :description => error.class.description,
            :errors      => []
          }
        end
        groups[error.class][:errors] << error
      }
      groups
    end


    def update_ui
      message = "Click on solids to inspect. Use arrow keys to cycle between "\
        "errors. Press Return to zoom to error. Press Tab/Shift+Tab to cycle "\
        "though errors and zoom."
      Sketchup.status_text = message
      nil
    end


    def zoom_to_error(view)
      error = filtered_errors[@current_error]
      view.zoom(error.entities)
      # Adjust camera for the instance transformation
      camera = view.camera

      point = view.camera.target
      offset = view.pixels_to_model(1000, point)
      #p offset
      offset_point = point.offset(view.camera.direction.reverse, offset)
      vector = point.vector_to(offset_point)
      if vector.valid?
        tr_offset = Geom::Transformation.new(vector)
        tr = @transformation * tr_offset
      else
        tr = @transformation
      end

      eye = camera.eye.transform(tr)
      target = camera.target.transform(tr)
      up = camera.up.transform(tr)
      view.camera.set(eye, target, up)
      nil
    end


    def draw_short_edge_error(error, view)
      edge = error.entities[0]

      leader_length = 15
      pt1 = screen_point(mid_point(edge), view)
      pt2 = pt1.offset(X_AXIS, leader_length)
      offset_vector = ORIGIN.vector_to(pt1)

      warning_color = Sketchup::Color.new(255, 153, 0)

      view.drawing_color = warning_color
      view.line_width = 2
      view.line_stipple = ''

      draw2d_point_square(pt1, 6, view)
      line = adjust([pt1, pt2], nil, false)
      view.draw2d(GL_LINES, pt1, pt2)

      triangle = [
        Geom::Point3d.new(leader_length,       8, 0),
        Geom::Point3d.new(leader_length + 16,  8, 0),
        Geom::Point3d.new(leader_length +  8, -8, 0)
      ]
      triangle = adjust(triangle, offset_vector, false)
      view.draw2d(GL_TRIANGLES, triangle)

      view.drawing_color = 'black'
      exclamation = [
        Geom::Point3d.new(leader_length + 8,  6, 0),
        Geom::Point3d.new(leader_length + 8,  4, 0),
        Geom::Point3d.new(leader_length + 8,  2, 0),
        Geom::Point3d.new(leader_length + 8, -3, 0)
      ]
      exclamation = adjust(exclamation, offset_vector, false)
      view.draw2d(GL_LINES, exclamation)

      nil
    end


    def draw2d_point_square(point, size, view)
      half_size = size / 2.0
      points = [
        point.offset([-half_size, -half_size, 0]),
        point.offset([ half_size, -half_size, 0]),
        point.offset([ half_size,  half_size, 0]),
        point.offset([-half_size,  half_size, 0])
      ]
      points = adjust(points, nil, false)
      view.draw2d(GL_QUADS, points)
    end


    def adjust(points, offset_vector = nil, odd_offset_width = true)
      if offset_vector && offset_vector.valid?
        points = points.map { |point| point.offset(offset_vector) }
      end
      # Adjust to pixel grid.
      points.map { |point|
        point.x = point.x.to_i
        point.y = point.y.to_i
        point.z = point.z.to_i
        if odd_offset_width
          point.x -= 0.5
          point.y -= 0.5
          point.z -= 0.5
        end
        point
      }
    end


    def mid_point(edge)
      pt1, pt2 = edge.vertices.map { |vertex| vertex.position }
      Geom.linear_combination(0.5, pt1, 0.5, pt2)
    end


    def screen_point(point, view)
      point2d = view.screen_coords(point)
      point2d.z = 0
      point2d
    end

  end # class InspectorTool
end # module TT::Plugins::SolidInspector2
