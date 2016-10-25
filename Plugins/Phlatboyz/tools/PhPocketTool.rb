#
# Name:		PocketTool.rb
# Desctiption:	Create a pocket face and zigzag edges
# Author:	Katsuhiko Toba ( http://www.eprcp.com/ )
# Usage:	1. Install into the plugins directory.
#		2. Select "Pocket" from the Plugins menu.
#		3. Click the face to pocket
#		4. Select "CenterLine Tool" from menu or toolbar
#		5. Click the zigzag edge first, the face edge second.
#		NOTE: Do not use Centerline from context menu.
#                     It breaks the zigzag edge.
# Limitations:	Simple convex face only
#
# ** Modified by kyyu 05-29-2010 - rewrote "get_offset_points" method because of a bug          **
#   where the pocket lines were out of the pocket boundaries because of mix direction edges     **
#   -Looks like it works, but not rigorously check so USE AT YOUR OWN RISK!                     **
#
# ** Modified by swarfer 2013-05-20 - press shift to only get zigzag, press ctrl to only get outline
#    This is a step on the way toward integrating it into Sketchucam, and properly handling complex faces
#
# ** Swarfer 2013-08-27 - integrated into Phlatscript toolset
#	default depth is 50% - no support for additional languages yet
#
#  swarfer May 2015 - use fuzzy stepover.  this makes the zigzag start and end at the same offset from the outline
#                   - use the stepover to set the offset.  used to use 0.1 offset of the zigzag from the outline, but   
#                       for larger offsets this does not make the best use of time.  now uses half the stepover for the offset
#                       up to 75%, then 1/3 up to 85%, then 1/4 - the offset cannot be allowed to grow too large, if it does
#                       you get pins left behind in the pocket, especially on curved edges.
#
#  swarfer Jul 2015 - apply pocket to all selected pockets if multiselected
# $Id$

require 'sketchup.rb'
#require 'Phlatboyz/Constants.rb'
require 'Phlatboyz/PhlatTool.rb'
require 'Phlatboyz/tools/CenterLineTool.rb'
require 'Phlatboyz/Tools/PhPocketCut.rb'
require 'Phlatboyz/PhlatOffset.rb'

module PhlatScript

   class PocketTool < CenterLineTool

   def initialize
      super()
      @limit = 0
      @flood = false #must we use flood file for zigzags?
      @active_face = nil
      @bit_diameter = PhlatScript.bitDiameter
      #puts "bit diameter #{@bit_diameter.to_mm}mm"
      @ip = nil

      # set this to change zigzag stepover, less for hard material, more for soft
      @stepover_percent = PhlatScript.stepover
      #               puts "stepover percent #{@stepover_percent}%"
      if (@stepover_percent <= 100)
         @stepOver = @stepover_percent / 100
      else
         @stepOver = 0.5
         @stepover_percent = 50
      end
      @keyflag = 0

      @tooltype   = 3
      @largeIcon  = "images/pockettool_large.png"
      @smallIcon  = "images/pockettool_small.png"
      @largeIcon  = "images/Pocket_large.png"
      @smallIcon  = "images/Pocket_small.png"
      @statusText = PhlatScript.getString("Pocket Face")
      #PhlatScript.getString("GCode")
      #	 @statusmsg = "Pockettool: [shift] for only zigzag [ctrl] for only boundary, stepover is #{@stepover_percent}%"
      @statusmsgBase  = "Pockettool: [shift] only Zigzag [ctrl] only boundary : [END] toggle direction : [HOME] floodfill ZZ only : "
      @statusmsg = @statusmsgBase
   end

   def enableVCB?
      return true
   end

   def statusText
      return @statusmsg
   end

   def onLButtonDown(flags, x, y, view)
      @ip.pick view, x, y
      @active_face = activeFaceFromInputPoint(@ip)
      if (@active_face)
         self.create_geometry(@active_face, view)
      end
      self.reset(view)
      view.lock_inference
   end

   #SWARFER, want to detect the shift key down, which will prevent drawing an offset line
   #  ie when shift pressed, only do the zigzag inside the current face
   #also detect CTRL, if pressed do not draw offset line, only zigzag
   def onKeyDown(key, repeat, flags, view)
      if key == VK_END    # toggle zig direction
         toggle_direc_flag()
      end
      if key == VK_HOME    # toggle use of flood fill
         @flood = !@flood
         if (@flood)
            @statusmsg = @statusmsgBase + "FLOOD #{@stepover_percent}%"
         else
            @statusmsg = @statusmsgBase + "StepOver #{@stepover_percent}%"
         end
         Sketchup::set_status_text(@statusmsg, SB_PROMPT)
      end

      if (key == VK_SHIFT)
         @keyflag = 1
      else
         if (key == VK_CONTROL)
            @keyflag = 2
         else
            super     #process other keys for depth selection
         end
      end
   end

   def onKeyUp(key, repeat, flags, view)
      if key = VK_SHIFT || key = VK_CONTROL
         @keyflag = 0
      end
      #puts "keyup keyflag = #{@keyflag}"
   end

   def draw(view)
      if (@active_face)
         self.draw_geometry(view)
      end
   end

   def onMouseMove(flags, x, y, view)
      @ip.pick view, x, y
      @active_face = activeFaceFromInputPoint(@ip)
      if (@active_face)
         view.tooltip = @ip.tooltip
      end
      view.invalidate if (@ip.display?)
      #reapply status text just in case a tooltip overwrote it
      Sketchup::set_status_text @statusmsg, SB_PROMPT
   end

   # VCB
   def onUserText(text,view)
      super(text,view)

=begin    now uses centerlinetool depth processing, same as foldtool
      begin
         parsed = text.to_f #do not use parse_length function
      rescue
         # Error parsing the text
         UI.beep
         @depth = 50.to_f
         parsed = 50.to_f
         Sketchup::set_status_text("#{@depth} default", SB_VCB_VALUE)
      end
      if (parsed < 1)
         parsed = 1
      end
      if (parsed > (2*PhlatScript.cutFactor))
         parsed = 2*PhlatScript.cutFactor
      end
      if (!parsed.nil?)
         @depth = parsed
         Sketchup::set_status_text("#{@depth} %", SB_VCB_VALUE)
         puts "New Plunge Depth " + @depth.to_s
      end
=end
   end

   def activeFaceFromInputPoint(inputPoint)
      face = inputPoint.face
      # check simple face (outer_loop only)
      if (!@flood)
         if (face)
            if (face.loops.length != 1)
               face = nil
            end
         end
      end
      return face
   end

   def cut_class
      return PocketCut
   end

   def activate
      super()
      @ip = Sketchup::InputPoint.new
      @bit_diameter = PhlatScript.bitDiameter
      @stepover_percent = PhlatScript.stepover
      #puts "activate stepover percent #{@stepover_percent}%"
      if @stepover_percent <= 100
         @stepOver = @stepover_percent.to_f / 100
      else
         @stepover_percent = 50.to_f
         @stepOver = 0.5.to_f
      end
      #if things are selected, try to pocket the faces then deselect
      if (Sketchup.active_model.selection.count > 1)
         view = Sketchup.active_model.active_view       
         sel = Sketchup.active_model.selection
         didit = false
         sel.each { |thing|
             if (thing.typename == 'Face') 
                #puts "#{thing}"
                @active_face = thing
                self.create_geometry(@active_face, view)
                didit = true
             end
             }
         sel.clear    if (didit)
         self.reset(view)    
         Sketchup.active_model.select_tool(nil) # select select tool since we have already pocketed all selected faces
      else  #if nothing selected, just get ready to pocket the clicked face
         @ip = Sketchup::InputPoint.new
         #puts "activate stepOver = #{@stepOver}  @stepover_percent #{@stepover_percent}"
         if (@flood)
            @statusmsg = @statusmsgBase + "FLOOD #{@stepover_percent}%"
         else
            @statusmsg = @statusmsgBase + "StepOver #{@stepover_percent}%"
         end
         Sketchup::set_status_text(@statusmsg, SB_PROMPT)
         self.reset(nil)
      end
   end
   
   #return true if any true values in hash 0..xm,0..ym
   def someleft(hsh, xm, ym)
      y = 0
      while (y <= ym) do
         x = 0
         while (x <= xm) do
            if hsh[[x,y]]
               return true
            end
            x += 1
         end
         y += 1
      end
      return false
   end

   # return true if pc is on the line pa,pb   
   def isonline(pc,pa,pb)
      ac = pa.distance(pc)
      cb = pb.distance(pc)
      ab = pa.distance(pb)
      return (ab -(ac + cb)).abs < 0.0001
   end   
  
   # return true if line [pt1,pt2] crosses any edge in theface
   def iscrossing(pt1,pt2, theface)
      line = [pt1, pt2]
      theface.loops.each { |loop|
         edges = loop.edges
         edges.each { |e|  #check each edge to see if it intersects line inside the edge
            l2 = [e.vertices[0].position, e.vertices[1].position]    # make a line
            point = Geom.intersect_line_line(line, e.vertices)       # find intersection
            if (point != nil)
               online1 = isonline(point, line[0], line[1])           # is the point on the line
               online2 = isonline(point, e.vertices[0].position, e.vertices[1].position)  # is the point on the edge
               #ent.add_cpoint(point)    if (online1 and online2)
               #puts "online1 #{online1} #{online2}"
               return true if (online1 and online2)
               # if (online1 and online2) then we can return true here, no need to process more
            end
         } # edges.each
      }   # loops.each
      return false
   end

   def debugfile(line)
      File.open("d:/temp/sketchupdebug.txt", "a+") { |fp| fp.puts(line)  }
   end
   
   
   # this can zigzag a face with holes in it, and also ones with complex concave/convex borders
   # returns an array containing one or more arrays of points, each set of points is a zigzag
   def get_zigzag_flood(aface)
      result = []
      
      # create a 2D array to hold the rasterized shape
      # raster is on stepover boundaries and center of each square is where the zigzags will start and end.
      # set true for each centerpoint that is inside the face
      # raster 0,0 is bottom left of the shape, just outside the boundary
      bb = aface.bounds
      stepOverinuse = @bit_diameter * @stepOver
      if ($phoptions.use_fuzzy_pockets?)  #always uses fuzzy, because it fails at exactly 50%
         ylen = bb.max.y - bb.min.y - 0.002
         stepOverinuse = getfuzzystepover(ylen)
         xlen = bb.max.x - bb.min.x - 0.002
         stepOverinuse += getfuzzystepover(xlen)
         stepOverinuse /= 2      # avg of horiz and vertical fuzzy step
      end
      ystart = bb.min.y - stepOverinuse / 2  # center of bottom row of cells
      yend = bb.max.y + stepOverinuse / 2 + 0.002
      
      xstart = bb.min.x - stepOverinuse / 2  # center of first column of cells
      xend = bb.max.x + stepOverinuse  * 3/4  # MUST have a false column after end of object
      debugfile("xstart #{xstart.to_mm},#{ystart.to_mm}   #{xend.to_mm},#{yend.to_mm} #{stepOverinuse.to_mm}" )   if (@debug)
      
      cells = Hash.new(false)
      # now loop through all cells and test to see if this point is in the face or on an edge
      pt = Geom::Point3d.new(0, 0, 0)
      x = xstart
      xmax = ymax = 0.0
      
 entities = Sketchup.active_model.active_entities
 #constpoint = entities.add_cpoint point1      
      countx = 0
      while (x <= xend) do
         y = ystart
#         s = "X #{x.to_mm}"
         county = 0
         while (y <= yend) do
            xc = ((x-xstart) / stepOverinuse + 0.002).round  # x cell index
            yc = ((y-ystart) / stepOverinuse + 0.002).round  # y cell index
            pt = Geom::Point3d.new(x, y,0)
            res = aface.classify_point(pt)
#            s += " #{y.to_mm}:#{xc}-#{yc}"
            
            case res
               when Sketchup::Face::PointUnknown #(indicates an error),
                  puts "unknown"    if (@debug)
               when Sketchup::Face::PointInside    #(point is on the face, not in a hole),
                  cells[[xc,yc]] = true
               when Sketchup::Face::PointOnVertex  #(point touches a vertex),
                  #cells[[xc,yc]] = true
               when Sketchup::Face::PointOnEdge    #(point is on an edge),
                  #cells[[xc,yc]] = true
               when Sketchup::Face::PointOutside   #(point outside the face or in a hole),
                  #puts "outside"      if (@debug)
               when Sketchup::Face::PointNotOnPlane #(point off the face's plane).
                  puts "notonplane"    if (@debug)
            end
            
            xmax = (xmax < xc) ? xc : xmax
            ymax = (ymax < yc) ? yc : ymax
            y += stepOverinuse
            county += 1
            if (county > 200)
               puts "county high break"
               break
            end
         end  # while y
#         debugfile(s)  if (@debug)
         x += stepOverinuse
         countx += 1
         if (countx > 200)
            puts "countx high break"
            break
         end
      end # while x
      debugfile("xmax #{xmax} ymax #{ymax}")  if (@debug) # max cell index
#      puts "xmax #{xmax} ymax #{ymax}"
#output array for debug      
      if (@debug)
         y = ymax
         debugfile("START")   if (@debug)
         while (y >= 0) do
            x = 0
            s = "y #{y}"
            while (x <= xmax) do
               if (cells[[x,y]])
                  s += " 1"
               else
                  s += " 0"
               end
               x += 1
            end
            debugfile(s)      if (@debug)
            y -= 1 
         end
      end

      # now create the zigzag points from the hash, search along X for first and last points
      # keep track of 'going left' or 'going right' so we can test for a line that would cross the boundary
      # if this line would cross the boundary, start a new array of points
      r = 0
      prevpt = nil
#@debug = true
      while (someleft(cells,xmax,ymax))  # true if some cells are still not processed
         debugfile("R=#{r}")           if (@debug)
         result[r] = []
         y = 0
         goingright = true
         py = -1  # previous y used, to make sure we do not jump a Y level
         county = 0
         while (y <= ymax) do
            county += 1
            if (county > 500)
               puts " county break"
               break
            end
         
            leftx = -1
            x = 0
            while (x <= xmax) do # search to the right for a true
               if (cells[[x,y]] == true)
                  cells[[x,y]] = false
                  leftx = x
                  break  # found left side X val
               end
               x += 1
            end #while x
            rightx = -1
            x += 1
            if x <= xmax 
               while (x <= xmax) do  # search to the right for a false
                  if (cells[[x,y]] == false)
                     rightx = x-1
                     break  # found right  side X val
                  end
                  cells[[x,y]] = false                # set false after we visit
                  x += 1
               end #while x
            end
            # now we have leftx and rightx for this Y, if rightx > -1 then push these points
            debugfile("   left #{leftx} right #{rightx} y #{y}")  if (@debug)
            if (rightx > -1)
               #if px,py does not cross any face edges
#               pt1 = Geom::Point3d.new(xstart + leftx*stepOverinuse, ystart + y * stepOverinuse, 0)
#               pt2 = Geom::Point3d.new(0, 0, 0)
               if (goingright)
                  pt = Geom::Point3d.new(xstart + leftx*stepOverinuse, ystart + y * stepOverinuse, 0)
                  
                  #if line from prevpt to pt crosses anything, start new line segment
                  if (prevpt != nil)
                     if (iscrossing(prevpt,pt,aface) )
                        debugfile("iscrossing goingright #{x} #{y}")      if (@debug)
                        r += 1
                        result[r] = []
                        debugfile(" R=#{r}")          if (@debug)
                        prevpt = nil
                     else
                        if (py > -1)
                           if ((y - py) > 1)  # do not cross many y rows, start new set instead
                              debugfile("isyrows goingright #{x} #{y}")       if (@debug)
                              r += 1
                              result[r] = []
                              debugfile(" R=#{r}")       if (@debug)
                              prevpt = nil
                           end
                        end
                     end
                  end
                  
                  entities.add_cpoint(pt)       if (@debug)
                  result[r] << pt
                  pt = Geom::Point3d.new(xstart + rightx*stepOverinuse, ystart + y * stepOverinuse, 0)
                  result[r] << pt
                  entities.add_cpoint(pt)       if (@debug)
               else
                  #pt.x = xstart + rightx*stepOverinuse
                  #pt.y = ystart + y * stepOverinuse
                  pt = Geom::Point3d.new(xstart + rightx*stepOverinuse, ystart + y * stepOverinuse, 0)
                  
                  #if line from prevpt to pt crosses anything, start new line segment
                  if (prevpt != nil)
                     if (iscrossing(prevpt,pt,aface) )
                        debugfile("iscrossing goingleft #{x} #{y}")     if (@debug)
                        prevpt = nil
                        r += 1
                        result[r] = []
                        debugfile(" R=#{r}")       if (@debug)
                     else   
                        if (py > -1)
                           if ((y - py) > 1)  # do not cross many y rows
                              debugfile("isyrows goingleft #{x} #{y}")     if (@debug)
                              r += 1
                              result[r] = []
                              prevpt = nil
                              debugfile(" R=#{r}")                         if (@debug)
                           end
                        end
                     end
                  end
                  
                  result[r] << pt
                  entities.add_cpoint(pt)    if (@debug)
                  #pt.x = xstart + leftx*stepOverinuse
                  pt = Geom::Point3d.new(xstart + leftx*stepOverinuse, ystart + y * stepOverinuse, 0)
                  result[r] << pt
                  entities.add_cpoint(pt)    if (@debug)
               end
               prevpt = Geom::Point3d.new(pt.x, pt.y, 0)
               py = y
            end # if rightx valid
            y += 1
            goingright = !goingright
         end # while y
         
         #debug output
         if (@debug)
            if (someleft(cells,xmax,ymax)  )
               debugfile("someleft #{r}")       if (@debug)
               yc = ymax
               while (yc >= 0) do
                  xc = 0
                  s = "Y #{yc}"
                  while (xc <= xmax) do
                     if (cells[[xc,yc]])
                        s += " 1"
                     else
                        s += " 0"
                     end
                     xc += 1
                  end
                  debugfile(s)         if (@debug)
                  yc -= 1 
               end
            end
         end
         r += 1
         prevpt = nil
      end # while someleft   
@debug = false
      puts " result #{result.length}  #{result[0].length}  "   if (@debug)
      debugfile("result #{result.length}")      if (@debug)
      result.each { |rs|
         debugfile("   #{rs.length}")           if (@debug)
         }
      return result
   end

#-------------------------------------------------------------
   def draw_geometry(view)
      view.drawing_color = Color_pocket_cut
      #view.line_width = 3.0
      
      # if face has holes then do flood zigzag only
      if (!@flood)
         if (@keyflag == 1) || (@keyflag == 0)
            zigzag_points = get_zigzag_points(@active_face.outer_loop)
         else
            zigzag_points = nil
         end

         if (@keyflag == 2) || (@keyflag == 0)
            contour_points = get_contour_points(@active_face.outer_loop) if (!@active_face.deleted?)
         else
            contour_points = nil
         end
         
         if (zigzag_points != nil)
            if (zigzag_points.length >= 2)
               view.draw(GL_LINE_STRIP, zigzag_points)
            end
         end
         if (contour_points != nil)
            if (contour_points.length >= 3)
               view.draw( GL_LINE_LOOP, contour_points)
            end
         end
      else  # do floodfill only
         puts "  #{@active_face.loops.length} loops"  if (@debug)
         zigzag_points = get_zigzag_flood(@active_face)      # returns array of arrays of points
         
         if (zigzag_points != nil)
            zigzag_points.each { |zpoints|
               puts "draw #{zpoints.length}" if (@debug)
#               debugfile("drawing #{zpoints.length}")
#               zpoints.each { |pt|
#                  debugfile("#{pt.x}  #{pt.y}")
#                  }
               view.draw(GL_LINE_STRIP, zpoints) if (zpoints.length > 1)
               }
         sleep(1)      if (@debug)
         end
      end

   end

   def create_geometry(face, view)
      #puts "create geometry"
      model = view.model
      model.start_operation("Create Pocket",true,true)
      
      if (@flood)
         zigzag_points = get_zigzag_flood(@active_face)      # returns array of arrays of points
         zigzag_points.each { |zpoints|
            if (zpoints.length > 1)
               zedges = model.entities.add_curve(zpoints)
               cuts = PocketCut.cut(zedges)
               cuts.each { |cut| cut.cut_factor = compute_fold_depth_factor }
            end
            }
         @flood = false   
      else
         if @keyflag == 1 || @keyflag == 0
            zigzag_points = get_zigzag_points(@active_face.outer_loop)
         else
            zigzag_points = nil
         end

         if (@keyflag == 2) || (@keyflag == 0)
            contour_points = get_contour_points(@active_face.outer_loop)
         else
            contour_points = nil
         end

         if zigzag_points != nil
            if (zigzag_points.length >= 2)
               zedges = model.entities.add_curve(zigzag_points)
               cuts = PocketCut.cut(zedges)
               cuts.each { |cut| cut.cut_factor = compute_fold_depth_factor }
            end
         end
         if (contour_points != nil)
            if (contour_points.length >= 3)
               contour_points.push(contour_points[0])  #close the loop for add_curve
   #use add_curve instead of add_face so that the entire outline can be selected easily for delete
               if PhlatScript.usePocketcw?
   #               puts "pocket CW"
   #               cface = model.entities.add_face(contour_points)
                  cedges = model.entities.add_curve(contour_points)
               else
   #               puts "pocket CCW"
   #               cface = model.entities.add_face(contour_points.reverse!)
   #               cedges = cface.edges
                  cedges = model.entities.add_curve(contour_points.reverse!)             # reverse points for counter clockwize loop
               end
               cuts = PocketCut.cut(cedges)
               cuts.each { |cut| cut.cut_factor = compute_fold_depth_factor }
            end
         end
      end

      model.commit_operation
   end

#----------------------------------------------------------------------
# generic offset points routine
#----------------------------------------------------------------------

   def get_intersect_points(lines)
      #               puts "Get intersect points"
      pts = []
      for i in 0..lines.length-1 do
         line1 = lines[i-1]      # array[-1] is equal to array[array.length-2]
         line2 = lines[i]
         pt = Geom::intersect_line_line(line1, line2)
         if (pt)
            pts << pt
         end
      end
      return pts
   end

   def get_offset_points(loop, offset)
      #               puts "get offset points"
      normal_vector = Geom::Vector3d.new(0,0,-1)
      lines = []
      r = []
      notr = []
      for edge in loop.edges
         if edge.reversed_in? @active_face then
            r.push edge
         else
            notr.push edge
         end
      end

      for edge in loop.edges
         pt1 = edge.start.position
         pt2 = edge.end.position

         line_vector = edge.line[1]
         line_vector.normalize!
         move_vector = line_vector * normal_vector
         move_vector.length = offset

         if r.length != 0 and notr.length != 0
            if edge.reversed_in? @active_face
               lines <<  [pt1.offset(move_vector.reverse), pt2.offset(move_vector.reverse)]
            else
               lines <<  [pt1.offset(move_vector), pt2.offset(move_vector)]
            end
         elsif r.length == 0
            lines <<  [pt1.offset(move_vector), pt2.offset(move_vector)]
         elsif notr.length == 0
            lines <<  [pt1.offset(move_vector.reverse), pt2.offset(move_vector.reverse)]
         end
      end #for

      points = get_intersect_points(lines)
      return points
   end

#----------------------------------------------------------------------
# contour
#----------------------------------------------------------------------

def get_contour_points(loop)
#               puts "get contour points"
#   return get_offset_points(loop, -(@bit_diameter * 0.5))
   return Offset.vertices(@active_face.outer_loop.vertices, -(@bit_diameter * 0.5)).offsetPoints
end

#----------------------------------------------------------------------
# zigzag
#----------------------------------------------------------------------
   # the old way, zigs along X axis
   def get_hatch_points_y(points, y)
      plane = [Geom::Point3d.new(0, y, 0), Geom::Vector3d.new(0,1,0)]
      pts = []
      for i in 0..points.length-1 do
         y1 = points[i-1].y
         y2 = points[i].y
         # very small differences in Y values will cause the following tests to 'next' when they should not
         # ie Y might display as 2.9mm but be 1e-17 different than the point.y, and y < y1 so you get no point
         # where you want a point
         # rather use signed differences
#         next if (y1 == y2)
#         next if ((y1 > y2) && ((y > y1) || (y < y2)))
#         next if ((y1 < y2) && ((y < y1) || (y > y2)))
#puts "y1 #{y1} y2 #{y2}"         
#         dif = (y1-y2).abs
         if ((y1 - y2).abs < 0.001)   #  small enough?
            next
         end
         d1 = y - y1
         d2 = y - y2
         if ((y1 > y2) && ((d1 > 0.0001) || (d2 < -0.0001)))
            next
         end
         if ((y1 < y2) && ((d1 < -0.0001) || (d2 > 0.0001)))
            next
         end

         line = [points[i-1], points[i]]
         pt = Geom::intersect_line_plane(line, plane)
#         if ((pt.x < 237.0) || (pt.x > 366.0))
#            puts "y1#{y1} y2#{y2} dif#{dif.to_mm} pt #{pt}  Y #{y.to_mm}  line #{line}"
#         end
         if (pt)
            pts << pt
         end
      end #for
      pts.uniq!
      return pts.sort{|a,b| a.x <=> b.x}
   end

   # the alternate way, zigs along Y axis - better for phlatprinters
   def get_hatch_points_x(points, x)
      plane = [Geom::Point3d.new(x, 0, 0), Geom::Vector3d.new(1,0,0)]
      pts = []
      for i in 0..points.length-1 do
         x1 = points[i-1].x
         x2 = points[i].x

#         next if (x1 == x2)
#         next if ((x1 > x2) && ((x > x1) || (x < x2)))
#         next if ((x1 < x2) && ((x < x1) || (x > x2)))
         if ((x1 - x2).abs < 0.001)
            next
         end
         d1 = x - x1
         d2 = x - x2
         if ((x1 > x2) && ((d1 > 0.0001) || (d2 < -0.0001)))  # the signs are important
            next
         end
         if ((x1 < x2) && ((d1 < -0.0001) || (d2 > 0.0001)))
            next
         end

         line = [points[i-1], points[i]]
#         puts "#{line} #{x.to_mm}"
         pt = Geom::intersect_line_plane(line, plane)
         if (pt)
            pts << pt
         end
      end #for
      pts.uniq!
      return pts.sort{|a,b| a.y <=> b.y}
   end
   
   #get the offset from the main loop for the zigzag lines
   def getOffset
      #as stepover get bigger, so the chance of missing bits around the edge inscreases, 
      #so make the offset smaller for large stepovers
      div = (@stepOver >= 0.75) ? 3 : 2
      if (@stepOver >= 0.85)
         div = 4
      end
      if @keyflag == 1
         offset = @bit_diameter * @stepOver / div
      else
         offset = @bit_diameter * 0.5 + @bit_diameter * @stepOver / div
      end
#      if @keyflag == 1   # then only zigzag
#         offset = @bit_diameter * 0.1
#      else
#         offset = @bit_diameter * 0.6  #zigzag plus outline so leave space for outline
#      end
      return offset
   end

   def get_zigzag_points_y(loop)
#      puts "get zigzag Y points #{@stepOver}"
      dir = 1
      zigzag_points = []
      offset = getOffset()
      #puts "   offset #{offset}"

#      offset_points = get_offset_points(loop, -(offset))
#      puts "old offset_points #{offset_points}"

      offset_points = Offset.vertices(@active_face.outer_loop.vertices, -(offset)).offsetPoints

#      puts "new offset_points #{offset_points}"

      bb = loop.face.bounds
      y = bb.min.y + offset + 0.0005
      
      stepOverinuse = @bit_diameter * @stepOver
      if ($phoptions.use_fuzzy_pockets?)
         if (@stepOver != 0.5)
            ylen = bb.max.y - bb.min.y - (2 * offset) - 0.002
            stepOverinuse = getfuzzystepover(ylen)
         end
      end
      yend = bb.max.y + 0.0005
      while (y < yend) do
         pts = get_hatch_points_y(offset_points, y)
         if (pts.length >= 2)
            if (dir == 1)
               zigzag_points << pts[0]
               zigzag_points << pts[1]
               dir = -1
            else
               zigzag_points << pts[1]
               zigzag_points << pts[0]
               dir = 1
            end
         end
         #puts "@stepOver #{@stepOver}  @stepover_percent #{@stepover_percent}"
         y = y + stepOverinuse
         if (stepOverinuse <= 0) # prevent infinite loop
            print "stepOver <= 0, #{@stepOver} #{@bit_diameter}"
            break;
         end
      end #while
      return zigzag_points
   end

   def get_zigzag_points_x(loop)
      #puts "get X zigzag points #{@stepOver}"
      dir = 1
      zigzag_points = []
      #if @keyflag == 1   # do only zigzag
      #   offset = @bit_diameter * 0.1
      #else
      #   offset = @bit_diameter * 0.6
      #end
      offset =  getOffset()
#      puts "offset #{offset.to_mm}"

      #offset_points = get_offset_points(loop, -(offset))
      offset_points = Offset.vertices(@active_face.outer_loop.vertices, -(offset)).offsetPoints      
      #puts "offset_points #{offset_points}"

      bb = loop.face.bounds
      x = bb.min.x + offset + 0.0005
      
      #fuzzy stepover
      stepOverinuse = @bit_diameter * @stepOver
      if ($phoptions.use_fuzzy_pockets?)
         if (@stepOver != 0.5)
            xlen = bb.max.x - bb.min.x - (2 * offset) - 0.002
            stepOverinuse = getfuzzystepover(xlen)
         end
      end
      
      xend = bb.max.x + 0.0005
      while (x < xend) do
         pts = get_hatch_points_x(offset_points, x)
#         puts "x #{x.to_mm} pts#{pts}"
         if (pts.length >= 2)
            if (dir == 1)
               zigzag_points << pts[0]
               zigzag_points << pts[1]
               dir = -1
            else
               zigzag_points << pts[1]
               zigzag_points << pts[0]
               dir = 1
            end
         end
         #puts "@stepOver #{@stepOver}  @stepover_percent #{@stepover_percent}"
         x = x + stepOverinuse
         if (stepOverinuse <= 0) # prevent infinite loop
            puts "stepOver <= 0, #{stepOverinuse} #{@bit_diameter}"
            break;
         end
      end #while
      return zigzag_points
   end
  
   
   # select between the options
   def get_zigzag_points(loop)
      if PhlatScript.pocketDirection?
         return get_zigzag_points_x(loop)  # zigs along Y - suites phlatprinter
      else
         return get_zigzag_points_y(loop)  # zigs along x - suites gantries
      end
   end
#=============================================================
   def getfuzzystepover(len)
      len = len.abs
      stepOverinuse = curstep = @bit_diameter * @stepOver
      
      steps = len / curstep
#      puts "steps #{steps} curstep #{curstep.to_mm} len #{len.to_mm}\n"
      if (@stepOver < 0.5)
         newsteps = (steps + 0.5).round   # step size gets smaller  
      else
         newsteps = (steps - 0.5).round  # step size gets bigger
      end   
      if (newsteps < 1)
#         puts " small newsteps #{newsteps}"
         newsteps = 2
      end
      newstep = len / newsteps
      newstepover = newstep / @bit_diameter
      
      while (newstepover > 1.0)  #this might never happen, but justincase
#         puts "  increasing steps #{newsteps}"
         newsteps += 1
         newstep = len / newsteps
         newstepover = newstep / @bit_diameter
      end
#      puts "   newstep #{newstep}"
      newstep = (newstep * 10000.0).floor / 10000.0   # floor to 1/10000"
      newstep = 1.mm if (newstep.abs < 0.001)
      
#      puts "    newsteps #{newsteps} newstep #{newstep.to_mm} newstepover #{newstepover}%\n"
      if (newstepover > 0)
         stepOverinuse = newstep
      end
      #puts ""
      return stepOverinuse           
   end   


   def toggle_direc_flag(model=Sketchup.active_model)
      val = model.get_attribute(Dict_name, Dict_pocket_direction, $phoptions.default_pocket_direction?)
      model.set_attribute(Dict_name, Dict_pocket_direction, !val)
   end


end #class

end #module
