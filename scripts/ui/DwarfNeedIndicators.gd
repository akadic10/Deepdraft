extends CanvasLayer

## Projected 2D badges, below windows and hidden by the normal loading gate.
## They never intercept clicks, alter needs, or create simulation agents.
const Concern = preload("res://scripts/components/DwarfConcern.gd")
const Picking = preload("res://scripts/components/ObjectPicking.gd")
@export var dwarf_director_path: NodePath
var _director: Node
var _config: Dictionary
var _entries: Dictionary = {}
var _remaining := 0.0


func _ready() -> void:
	layer = 19
	_director = get_node_or_null(dwarf_director_path)
	_config = UIRegistry.get_dwarf_indicators()
	process_priority = 10 # Project after the camera/actors have moved.


func _process(delta: float) -> void:
	if not visible:
		_remaining = 0.0
		return
	_remaining -= delta
	var check_visibility := _remaining <= 0.0
	if check_visibility:
		_remaining = float(_config.refresh_seconds)
		refresh()
	var camera := get_viewport().get_camera_3d()
	for entry: Dictionary in _entries.values():
		if camera == null or not is_instance_valid(entry.agent):
			entry.icon.hide()
			continue
		_update_marker(entry,camera,delta,check_visibility)


func refresh() -> void:
	var present := {}
	var roster: Array = _director.get_roster() if is_instance_valid(_director) else []
	for agent: DwarfAgent in roster:
		var id := agent.get_instance_id()
		present[id] = true
		var issue := Concern.describe(agent)
		if not _entries.has(id):
			if issue.is_empty(): continue
			var icon := TextureRect.new()
			icon.name = "Need_%d" % agent.dwarf_id
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.hide()
			add_child(icon)
			_entries[id] = {"agent":agent,"icon":icon,"issue":{},"key":"","pulse":0.0,"alpha":0.0,"clear":false,"checked":false}
		var entry: Dictionary = _entries[id]
		var key := String(issue.kind)+String(issue.title) if not issue.is_empty() else ""
		if key != entry.key:
			entry.key = key
			entry.pulse = 0.0
			if not issue.is_empty(): entry.icon.texture = UIRegistry.get_need_icon(issue.kind)
		entry.issue = issue
	for id: int in _entries.keys():
		if present.has(id): continue
		_entries[id].icon.queue_free()
		_entries.erase(id)


func _update_marker(entry: Dictionary, camera: Camera3D, delta: float, check_visibility: bool) -> void:
	var agent: DwarfAgent = entry.agent
	var icon: TextureRect = entry.icon
	entry.alpha = move_toward(float(entry.alpha),0.0 if entry.issue.is_empty() else 1.0,delta/float(_config.fade_seconds))
	entry.pulse += delta
	icon.hide()
	if entry.alpha<=0.0 or not agent.is_visible_in_tree() or agent.is_queued_for_deletion(): return
	var bounds := Picking.visible_world_bounds(agent._head)
	if bounds.size == Vector3.ZERO: return
	var head := bounds.get_center()
	var anchor := Vector3(head.x,bounds.end.y,head.z)
	if camera.is_position_behind(anchor): return
	var viewport_size := get_viewport().get_visible_rect().size
	var ui_scale := clampf(viewport_size.y/1080.0,0.8,2.0)
	var projected_height := camera.unproject_position(agent.global_position).distance_to(camera.unproject_position(agent.global_position+Vector3.UP*3.3))
	var minimum := float(_config.minimum_dwarf_pixels)*ui_scale
	if projected_height<=minimum: return
	var zoom_alpha := smoothstep(minimum,minimum*1.8,projected_height)
	var pulse := 1.0+0.12*sin(PI*clampf(float(entry.pulse)/float(_config.pulse_seconds),0.0,1.0))
	var width := float(_config.icon_pixels)*ui_scale*pulse
	icon.size = Vector2(width,width*1.125)
	icon.position = camera.unproject_position(anchor)-Vector2(width*.5,icon.size.y+6.0*ui_scale)
	if not Rect2(Vector2.ZERO,viewport_size).encloses(icon.get_rect()): return
	if check_visibility or not entry.checked:
		entry.clear = _head_visible(camera,head,agent._slice_y)
		entry.checked = true
	if not entry.clear: return
	icon.modulate.a = float(entry.alpha)*zoom_alpha
	icon.show()


func _head_visible(camera: Camera3D, head: Vector3, slice_y: int) -> bool:
	var screen := camera.unproject_position(head)
	var start := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen).normalized()
	var distance := start.distance_to(head)
	var visible_face := Callable()
	var underground := get_tree().get_first_node_in_group("underground_view")
	if underground != null and underground.is_inspecting(): visible_face = underground.is_terrain_face_visible
	return Picking.terrain_hit(start,direction,slice_y,maxf(0.0,distance-.1),Callable(),visible_face).is_empty()
