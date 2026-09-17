extends RefCounted
## Original 32x48, twelve-direction actor; eight distance-driven walk poses.
static var cache: Dictionary = {}
static func stroke(image: Image, start: Vector2, finish: Vector2, color: Color, width: int = 2) -> void:
 var length := maxi(1,ceili(start.distance_to(finish)*2))
 for i in length+1:
  var point := start.lerp(finish,float(i)/length)
  var rect := Rect2i(roundi(point.x),roundi(point.y),width,width).intersection(Rect2i(0,0,image.get_width(),image.get_height()))
  if rect.has_area(): image.fill_rect(rect,color)

static func texture(direction: int, step: int, crouch: bool, outline: bool = false, move_direction: int = -1, pose: int = 0, enemy: bool = false, arm_phase: int = -1, weight: int = 0, draw_phase: int = -1) -> Texture2D:
 if move_direction < 0: move_direction = direction
 var key := "%s/%s/%s/%s/%s/%s/%s/%s/%s/%s" % [direction,step,crouch,outline,move_direction,pose,enemy,arm_phase,weight,draw_phase]
 if cache.has(key): return cache[key]
 var image := Image.create(32,48,false,Image.FORMAT_RGBA8)
 var angle := direction*PI/6
 var walk_angle := move_direction*PI/6
 var phase := maxf(step,0)/8.0*TAU
 var walking := step>=0
 var back := direction in [4,5,6,7,8]
 var ink := Color("283239")
 var coat := Color("526f7a") if not enemy else Color("88574f")
 var light := Color("84a1a2") if not enemy else Color("b08064")
 var leather := Color("6e5239")
 var skin := Color("d1ac83")
 var hip_y := 36 if crouch else 32
 var head_y := 16 if crouch else 6
 var shoulder_y := 26 if crouch else 21
 var width := roundi(14-4*absf(sin(angle)))
 var body_shift := roundi(sin(angle)*weight)
 var left := (32-width)/2 as int
 left+=body_shift
 # Alternating support feet stay at the ground anchor while knees articulate.
 for leg in 2:
  var cycle := phase+leg*PI
  var stride := cos(cycle)*(3.5 if walking else 0.0)
  var lift := maxf(0,sin(cycle))*(4.0 if walking else 0.0)
  var hip := Vector2(13+leg*4,hip_y)
  var foot := Vector2(hip.x+sin(walk_angle)*stride,45-lift)
  var knee := hip.lerp(foot,0.55)+Vector2(sin(walk_angle)*maxf(0,sin(cycle))*0.6,-lift*0.15)
  stroke(image,hip,knee,ink,4)
  stroke(image,hip+Vector2.ONE,knee,Color("526168"),2)
  stroke(image,knee,foot-Vector2(0,2),Color("36454c"),3)
  stroke(image,foot-Vector2(1,0),foot+Vector2(2,0),Color("332f2a"),3)
 # Tunic silhouette, shoulder mantle, belt, buckle and side pouch.
 image.fill_rect(Rect2i(left,shoulder_y,width,hip_y-shoulder_y+2),ink)
 image.fill_rect(Rect2i(left+1,shoulder_y+1,width-2,hip_y-shoulder_y),coat)
 image.fill_rect(Rect2i(left+2,shoulder_y,width-4,3),light)
 image.fill_rect(Rect2i(left,hip_y-2,width,3),leather)
 image.fill_rect(Rect2i(left+width-3,hip_y-2,4,5),Color("493d31"))
 if not back: image.fill_rect(Rect2i(15,hip_y-2,2,2),Color("c3a267"))
 else:
  image.fill_rect(Rect2i(12,shoulder_y+4,8,7),leather)
  image.fill_rect(Rect2i(13,shoulder_y+4,6,2),Color("957447"))
 # Chamfered head silhouette and a directional nose/ear rather than a flat square.
 image.fill_rect(Rect2i(11,head_y,10,14),ink)
 image.fill_rect(Rect2i(10,head_y+3,12,8),ink)
 image.fill_rect(Rect2i(12,head_y+1,8,5),Color("65503c") if not enemy else Color("758489"))
 image.fill_rect(Rect2i(12,head_y+6,8,6),skin if not back else Color("554735"))
 image.fill_rect(Rect2i(12,head_y+1,7,2),Color("957349") if not enemy else Color("adb4ac"))
 if back and absf(sin(angle))>0.2:
  image.fill_rect(Rect2i(11 if sin(angle)<0 else 20,head_y+8,1,3),skin)
 if not back:
  var nose := 15+roundi(sin(angle)*5)
  image.fill_rect(Rect2i(nose,head_y+8,2,3),skin.lightened(0.12))
  image.fill_rect(Rect2i(clampi(nose,12,19),head_y+7,1,1),ink)
 var hand_angle := angle
 if pose == 1: hand_angle -= 0.9
 if pose == 2: hand_angle += 0.8
 if pose == 3: hand_angle += 0.4
 if arm_phase>=0: hand_angle=angle+lerpf(-0.9,0.8,arm_phase/24.0)
 for arm in 2:
  var shoulder := Vector2(left-1 if arm==0 else left+width-1,shoulder_y+2)
  var hand := shoulder+Vector2(0,8)
  if pose > 0:
   hand = Vector2(15+sin(hand_angle)*9+(arm*2-1),shoulder_y+6+cos(hand_angle)*4)
   if pose == 4:
    var draw := 1.0 if draw_phase<0 else draw_phase/8.0
    var front := Vector2(15+sin(angle)*10,shoulder_y+4+cos(angle)*4)
    hand=front if arm==0 else front.lerp(Vector2(15-sin(angle)*2,shoulder_y+2),draw)
   hand.x+=body_shift
  elif arm==1:
   # Keep the weapon arm in a ready pose between attacks, avoiding an
   # instantaneous jump from dangling hands to a forward weapon grip.
   hand=Vector2(16+sin(angle)*7,shoulder_y+6+cos(angle)*3)
  elif walking:
   hand += Vector2(sin(walk_angle)*sin(phase+arm*PI)*3,cos(walk_angle)*cos(phase+arm*PI)*2)
  var elbow := shoulder.lerp(hand,0.55)+Vector2(-1 if arm==0 else 1,1)
  stroke(image,shoulder,elbow,ink,4)
  stroke(image,shoulder+Vector2.ONE,elbow,coat,2)
  stroke(image,elbow,hand,leather,3)
  stroke(image,hand,hand+Vector2(1,0),skin,2)
 if outline:
  var border := Image.create(32,48,false,Image.FORMAT_RGBA8)
  for y in range(1,48):
   for x in range(1,31):
    if image.get_pixel(x,y).a>0: continue
    if image.get_pixel(x-1,y).a>0 or image.get_pixel(x+1,y).a>0 or image.get_pixel(x,y-1).a>0 or (y<47 and image.get_pixel(x,y+1).a>0): border.set_pixel(x,y,Color("ffe3a0"))
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
