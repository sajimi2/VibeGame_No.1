extends Node3D
## Painted contact shadow aligned to the real supporting surface.
var radius := 0.4
var patch: MeshInstance3D
static var shadow_texture: Texture2D
func _ready() -> void:
 patch = MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(radius * 2, radius * 1.4)
 patch.mesh = plane
 patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var mat := StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
 mat.albedo_color = Color(0.12,0.15,0.17,0.5)
 if shadow_texture == null:
  var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
  for y in 32:
   for x in 32:
    var distance := Vector2((x-15.5)/15.5,(y-15.5)/15.5).length()
    image.set_pixel(x,y,Color(1,1,1,0.8 if distance < 0.7 else 0.4 if distance < 0.95 else 0))
  shadow_texture = ImageTexture.create_from_image(image)
 mat.albedo_texture = shadow_texture
 patch.material_override = mat
 add_child(patch)
 process_physics_priority = 8
func _physics_process(_delta: float) -> void:
 var anchor: Vector3 = get_parent().global_position
 var query := PhysicsRayQueryParameters3D.create(anchor+Vector3.UP*0.25,anchor+Vector3.DOWN*3,1)
 var hit := get_world_3d().direct_space_state.intersect_ray(query)
 patch.visible = not hit.is_empty()
 if hit.is_empty(): return
 var normal: Vector3 = hit.normal
 var right := normal.cross(Vector3.BACK).normalized()
 if right.length() < 0.1: right = Vector3.RIGHT
 patch.global_transform = Transform3D(Basis(right,normal,right.cross(normal)),hit.position+normal*0.018)
