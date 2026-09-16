extends RefCounted
## Original twelve-heading pixel actor with an eight-phase planted-foot walk.
static var cache: Dictionary = {}
static func stroke(image: Image, start: Vector2, finish: Vector2, color: Color, width: int = 2) -> void:
 var length := maxi(1, ceili(start.distance_to(finish) * 2))
 for i in length + 1:
  var point := start.lerp(finish, float(i) / length)
  var rect := Rect2i(roundi(point.x),roundi(point.y),width,width).intersection(Rect2i(0,0,24,32))
  if rect.has_area(): image.fill_rect(rect,color)

static func texture(direction: int, step: int, crouch: bool, outline: bool = false, move_direction: int = -1) -> Texture2D:
 if move_direction < 0: move_direction = direction
 var key := "%s/%s/%s/%s/%s" % [direction,step,crouch,outline,move_direction]
 if cache.has(key): return cache[key]
 var image := Image.create(24,32,false,Image.FORMAT_RGBA8)
 var angle := direction * PI / 6
 var walking := step >= 0
 var phase := maxf(0,step) / 8.0 * TAU
 var walk_angle := move_direction * PI / 6
 var back := direction in [4,5,6,7,8]
 var dark := Color("252c32")
 var coat := Color("548589") if not back else Color("43666f")
 var body_width := roundi(11 - 3 * absf(sin(angle)))
 var left := (24 - body_width) / 2 as int
 var hip_y := 23 if crouch else 21
 # One leg bears weight while the opposite foot lifts; torso remains stable.
 for leg in 2:
  var cycle := phase + leg * PI
  var stride := cos(cycle) * (3.5 if walking else 0.0)
  var lift := maxf(0,sin(cycle)) * (3.0 if walking else 0.0)
  var hip := Vector2(8 + leg*6,hip_y)
  var foot := Vector2(hip.x + sin(walk_angle)*stride,30 - lift)
  var knee := hip.lerp(foot,0.52) + Vector2(sin(walk_angle)*maxf(0,sin(cycle))*1.4 + cos(walk_angle)*stride*0.35,-lift*0.2)
  stroke(image,hip,knee,Color("344149") if leg == 0 else Color("4e5d65"),3)
  stroke(image,knee,foot-Vector2(0,1),Color("344149") if leg == 0 else Color("4e5d65"),2)
  stroke(image,foot-Vector2(1,0),foot+Vector2(1,0),dark,2)
 var shift := 3 if crouch else 0
 image.fill_rect(Rect2i(left,12+shift,body_width,10-shift),dark)
 image.fill_rect(Rect2i(left+1,13+shift,body_width-2,8-shift),coat)
 image.fill_rect(Rect2i(left+2,12+shift,body_width-4,2),Color("7ca2a0"))
 image.fill_rect(Rect2i(left,21,body_width,2),Color("7d6846"))
 image.fill_rect(Rect2i(8,3+shift,8,10),dark)
 image.fill_rect(Rect2i(9,3+shift,6,4),Color("796249"))
 image.fill_rect(Rect2i(9,7+shift,6,5),Color("cdab85") if not back else Color("604d3e"))
 if not back:
  var eye_x := 11 + roundi(sin(angle)*3)
  image.fill_rect(Rect2i(eye_x,8+shift,1,2),dark)
 if direction in [1,2,10,11]:
  image.fill_rect(Rect2i(8+direction if direction < 3 else 15-(12-direction),5+shift,1,7),Color("604d3e"))
 for arm in 2:
  var shoulder := Vector2(left-1 if arm == 0 else left+body_width,14+shift)
  var swing: float = sin(phase+arm*PI) * (1.8 if walking else 0)
  var forward: float = cos(phase+arm*PI) * cos(walk_angle) * (1.5 if walking else 0.0)
  var elbow := shoulder + Vector2(sin(walk_angle)*swing,3 + forward*0.5)
  var hand := shoulder + Vector2(sin(walk_angle)*swing*1.5,5+forward)
  stroke(image,shoulder,elbow,coat,2)
  stroke(image,elbow,hand,Color("cdab85"),2)
 if back:
  image.fill_rect(Rect2i(9+roundi(sin(angle)*3),14+shift,5,5),Color("725f43"))
 if outline:
  var border := Image.create(24,32,false,Image.FORMAT_RGBA8)
  for y in range(1,32):
   for x in range(1,23):
    if image.get_pixel(x,y).a > 0: continue
    if image.get_pixel(x-1,y).a > 0 or image.get_pixel(x+1,y).a > 0 or image.get_pixel(x,y-1).a > 0 or (y < 31 and image.get_pixel(x,y+1).a > 0):
     border.set_pixel(x,y,Color("ffe3a0"))
  image = border
 var result := ImageTexture.create_from_image(image)
 cache[key] = result
 return result
static func tree() -> Texture2D:
 if cache.has("tree"): return cache.tree
 var image := Image.create(48, 64, false, Image.FORMAT_RGBA8)
 # Forked trunk and root flare; last opaque row remains at y=61.
 for y in range(26,62):
  var width := 3 if y < 56 else 3 + (y-56)/2
  for x in range(23-width,26+width):
   image.set_pixel(x,y,Color("65533c") if x < 25 else Color("3b3830"))
 for i in range(14):
  image.fill_rect(Rect2i(12+i,29+i,3,2),Color("514332"))
  image.fill_rect(Rect2i(25+i,40-i,3,2),Color("514332"))
 var lobes := [Vector3(29,31,15),Vector3(13,30,11),Vector3(35,22,10),Vector3(21,20,16),Vector3(14,15,10),Vector3(29,10,9)]
 for lobe in lobes:
  for y in range(1,47):
   for x in range(1,47):
    var d := Vector2((x-lobe.x)/lobe.z,(y-lobe.y)/(lobe.z*0.78))
    var edge := 0.94 + 0.06*sin(atan2(d.y,d.x)*9)
    if d.length_squared() > edge: continue
    var light := (d + Vector2(0.28,0.35)).length()
    var col := Color("354d3b") if light > 1.05 else Color("496447") if light > 0.65 else Color("648050")
    if d.length_squared() > 0.8 and d.y > 0: col = Color("354d3b")
    if light < 0.7 and (x/3+y/2)%5 == 0: col = Color("7b945e")
    image.set_pixel(x,y,col)
 cache.tree = ImageTexture.create_from_image(image)
 return cache.tree
