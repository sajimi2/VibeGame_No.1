extends SceneTree
const Art = preload("res://scripts/tactical/directional_art.gd")
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func frames(n: int):
 for i in n: await physics_frame
func check(value: bool, message: String):
 checks += 1
 if not value: failures += 1
 print("%s %s" % ["PASS" if value else "FAIL", message])
func run():
 var lab = load("res://scenes/tactical_height.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 var actor = lab.player
 actor.test_mode = true
 await frames(10)
 var sheet := Image.create(24*8,32*3,false,Image.FORMAT_RGBA8)
 sheet.fill(Color("596350"))
 for row in 3:
  var hashes := {}
  var direction: int = [0,2,3][row]
  for frame in 8:
   var image := Art.texture(direction,frame,false,false,direction).get_image()
   hashes[hash(image.get_data())] = true
   sheet.blit_rect(image,Rect2i(0,0,24,32),Vector2i(frame*24,row*32))
   var contact := false
   for x in 24:
    if image.get_pixel(x,31).a > 0: contact = true
   check(contact,"at least one planted foot: direction %d frame %d" % [direction,frame])
  check(hashes.size() >= 6,"distinct gait poses for direction %d" % direction)
 sheet.resize(768,384,Image.INTERPOLATE_NEAREST)
 sheet.save_png("res://work/walk_cycle_sheet.png")
 check(actor.sprite.position == Vector3.ZERO and actor.sprite.offset == Vector2(0,16),"sprite pivot remains at feet")
 check(actor.sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"tilted paper no longer casts detached shadow")
 check(actor.shadow.patch.global_position.distance_to(actor.global_position) < 0.08,"contact shadow lies directly under feet")
 actor.position = Vector3(-6,0.1,2.5)
 actor.velocity = Vector3.ZERO
 actor.test_motion = Vector2(0,-1)
 await frames(80)
 var pose = actor.sprite.texture
 await frames(20)
 check(actor.sprite.texture == pose,"blocked actor stops gait instead of walking in place")
 check(lab.material("stone").diffuse_mode == BaseMaterial3D.DIFFUSE_TOON,"toon lighting enabled")
 lab.toggle_shading()
 check(lab.material("stone").diffuse_mode == BaseMaterial3D.DIFFUSE_BURLEY,"continuous lighting available for comparison")
 lab.toggle_shading()
 print("VISUAL_POLISH: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
