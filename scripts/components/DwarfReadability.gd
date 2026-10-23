extends Node

## A faint silhouette continues the oversized visual body behind nearby walls
## and ladder rungs. It shares each animated mesh transform, never changes the
## logical navigation footprint, and inherits slice/eye/actor visibility. Only
## actual nearby terrain/ladder cover qualifies, never the dwarf's own body.
const MAX_COLUMNS := 40
var agent: DwarfAgent
var material: ShaderMaterial
var _timer := 0.0
var _refresh_seconds := .2
var _silhouettes: Array[MeshInstance3D] = []

static func attach(dwarf: DwarfAgent) -> void:
	var helper := new()
	helper.name = "Readability"
	helper.agent = dwarf
	helper.material = ShaderMaterial.new()
	helper.material.shader = preload("res://scripts/shaders/dwarf_occlusion.gdshader")
	var config := TaskManager.get_config_section("readability")
	var tint := Color(String(config.get("color","b6ac90")))
	tint.a = float(config.get("opacity",.18))
	helper.material.set_shader_parameter("silhouette_color",tint)
	helper.material.set_shader_parameter("max_cover_depth",float(config.get("max_cover_depth",2.5)))
	helper._refresh_seconds = float(config.get("refresh_seconds",.2))
	for source: MeshInstance3D in dwarf.find_children("*","MeshInstance3D",true,false):
		if source.mesh == null: continue
		# A shadow-only proxy must never gain a visible occlusion silhouette.
		if preload("res://scripts/components/VoxelShadowSetup.gd").is_proxy(source): continue
		# Eyes and eyelids need no extra silhouette over their own head.
		if source.get_parent().name in ["MeshEyes","RestEyelids"]: continue
		var ghost := MeshInstance3D.new()
		ghost.name = "OccludedSilhouette"
		ghost.mesh = source.mesh
		ghost.material_override = helper.material
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		ghost.visible = false
		source.add_child(ghost)
		helper._silhouettes.append(ghost)
	dwarf.add_child(helper)

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0 or not agent.is_visible_in_tree(): return
	_timer = _refresh_seconds
	refresh()

func refresh() -> void:
	var here := agent.current_cell()
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	# Compress each nearby solid column into runs; bounded work per actor.
	for x in range(here.x-2,here.x+3):
		for z in range(here.z-2,here.z+3):
			var start := -1
			for y in range(here.y+1,here.y+6):
				var solid := y<here.y+5 and BlockRegistry.is_solid(WorldData.get_live_block(x,y,z))
				if solid and start<0: start = y
				if not solid and start>=0:
					lower.append(Vector3(x,start,z))
					upper.append(Vector3(x+1,y,z+1))
					start = -1
	for ladder: Dictionary in NavGrid.ladder_records():
		var base: Vector3i = ladder.base
		if absi(base.x-here.x)>2 or absi(base.z-here.z)>2: continue
		# A ladder covers the thin rail/rung slab, not its whole climbing column.
		var facing: Vector3 = Vector3(ladder.facing)
		var center := Vector3(base)+Vector3(.5,1+float(ladder.height)*.5,.5)+facing*.125
		var half := Vector3(.375,float(ladder.height)*.5,.25) if facing.z!=0 else Vector3(.25,float(ladder.height)*.5,.375)
		lower.append(center-half)
		upper.append(center+half)
	var count := mini(lower.size(),MAX_COLUMNS)
	lower.resize(MAX_COLUMNS)
	upper.resize(MAX_COLUMNS)
	material.set_shader_parameter("cover_lower",lower)
	material.set_shader_parameter("cover_upper",upper)
	material.set_shader_parameter("cover_count",count)
	for mesh in _silhouettes: mesh.visible = count>0
