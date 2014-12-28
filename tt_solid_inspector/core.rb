#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
begin
  require 'TT_Lib2/core.rb'
rescue LoadError => e
  module TT
    if @lib2_update.nil?
      url = 'http://www.thomthom.net/software/sketchup/tt_lib2/errors/not-installed'
      options = {
        :dialog_title => 'TT_Lib² Not Installed',
        :scrollable => false, :resizable => false, :left => 200, :top => 200
      }
      w = UI::WebDialog.new( options )
      w.set_size( 500, 300 )
      w.set_url( "#{url}?plugin=#{File.basename( __FILE__ )}" )
      w.show
      @lib2_update = w
    end
  end
end


#-------------------------------------------------------------------------------

if defined?( TT::Lib ) && TT::Lib.compatible?( '2.7.0', 'Solid Inspector' )

module TT::Plugins::SolidInspector

  require File.join( PATH, "upgrade.rb" )


  ### MENU & TOOLBARS ### ------------------------------------------------------

  unless file_loaded?( __FILE__ )
    m = TT.menu( 'Tools' )
    m.add_item( 'Solid Inspector' )  { self.inspect_solid }

    file_loaded( __FILE__ )
  end


  ### MAIN SCRIPT ### ----------------------------------------------------------

  # @since 1.0.0
  def self.inspect_solid
    Sketchup.active_model.tools.push_tool( SolidInspector.new )
  end


  # @since 1.0.0
  class SolidInspector

    # @since 1.0.0
    def initialize
      @instance = nil
      @errors = []
      @current_error = 0
      @groups = []

      @status = "Click on solids to inspect. Use arrow keys to cycle between errors. Press Return to zoom to error. Press Tab/Shift+Tab to cycle though errors and zoom."

      if Sketchup.active_model.selection.empty?
        analyze( nil )
      else
        Sketchup.active_model.selection.each { |e|
          next unless TT::Instance.is?(e)
          analyze(e)
          break
        }
      end
    end

    # @since 1.0.0
    def analyze(instance)
      @instance = instance

      if @instance
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add( @instance )
        entities = TT::Instance.definition(@instance).entities
        @transformation = @instance.transformation
      else
        entities = Sketchup.active_model.active_entities
        @transformation = Geom::Transformation.new()
      end

      # Any edge without two faces means an error in the surface of the solid.
      @current_error = 0
      @errors = entities.select { |e|
        e.is_a?( Sketchup::Edge ) && e.faces.length != 2
      }

      # Group connected error-edges.
      @groups = []
      stack = @errors.clone
      until stack.empty?
        cluster = []
        cluster << stack.shift

        # Find connected errors
        edge = cluster.first
        haystack = ([edge.start.edges + edge.end.edges] - [edge]).first & stack
        until haystack.empty?
          e = haystack.shift

          if stack.include?( e )
            cluster << e
            stack.delete( e )
            haystack += ([e.start.edges + e.end.edges] - [e]).first & stack
          end
        end

        @groups << cluster
      end
    end

    # @since 1.0.0
    def activate
      Sketchup.active_model.active_view.invalidate
      Sketchup.status_text = @status
    end

    # @since 1.0.0
    def deactivate(view)
      view.invalidate
    end

    # @since 1.0.0
    def resume(view)
      view.invalidate
      Sketchup.status_text = @status
    end

    # @since 1.0.0
    def onLButtonUp(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      if TT::Instance.is?( ph.best_picked )
        analyze( ph.best_picked )
      end
      view.invalidate
    end

    # @since 1.0.0
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

      #p key
      view.invalidate
    end

    # @since 1.0.0
    def zoom_to_error(view)
      e = @groups[ @current_error ]
      view.zoom( e )
      # Adjust camera for the instance transformation
      camera = view.camera
      t = @transformation
      eye = camera.eye.transform( t )
      target = camera.target.transform( t )
      up = camera.up.transform( t )
      view.camera.set( eye, target, up )
    end

    # @since 1.0.0
    def draw(view)
      view.line_width = 3
      view.line_stipple = ''

      unless @groups.empty?
        @groups.each_index { |index|
          error = @groups[index]

          view.drawing_color = (index == @current_error) ? 'red' : 'orange'

          # Get points for each error edge
          pts = error.map { |e| e.vertices.map{|v|v.position} }.flatten
          pts.map! { |pt| pt.transform( @transformation ) }

          view.draw(GL_LINES, pts)

          # Draw Attention Circle
          pts2d = pts.map { |pt| view.screen_coords(pt) }

          bb = Geom::BoundingBox.new
          bb.add( pts2d )
          size = bb.corner(0).distance( bb.corner(7) )
          size = 20 if size < 20 # Ensure a minimum size of the circle

          c = TT::Geom3d.circle( bb.center, Z_AXIS, size, 64 )
          view.draw2d( GL_LINE_LOOP, c )
        }
      end
    end

  end # class SolidInspector


  ### DEBUG ### ------------------------------------------------------------

  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::SolidInspector.reload
  #
  # @param [Boolean] tt_lib Reloads TT_Lib2 if +true+.
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    TT::Lib.reload if tt_lib
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end

end # module

end # if TT_Lib
