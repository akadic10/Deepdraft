extends "TreeRedesignPreview.gd"

## Isolated native-asset seating mock-up; no colony logic or saved furniture.
## Shared authoring frame / signed hand and foot mirroring matches DwarfAgent.
var _seated: Array[Dictionary] = []
var _chosen := "Personal room"
var _angle := "Three-quarter"
var _clearance := false
var _animate := true
var _time := 0.0
var _notes := Label.new()
var _envelopes := Node3D.new()
var _report: Array = []
var _table: Node3D

const STYLES := [
	["elder", "hair_m_braided_back", "beard_full_long", "brows_m_bushy", "medium", "white"],
	["adult", "hair_f_braid_side", "", "brows_f_thin_arched", "pale", "red"],
	["middle", "hair_m_wild_loose", "beard_forked", "brows_m_thick_flat", "dark", "brown"],
	["young", "hair_f_twin_braids", "", "brows_f_sharp_angled", "medium", "black"],
	["elder", "hair_m_short_back", "beard_full_braided", "brows_m_arched", "tan", "grey"],
	["adult", "hair_f_loose_long", "", "brows_f_bushy", "dark", "red"],
	["elder", "hair_m_shaved", "beard_braided_long", "brows_m_bushy", "pale", "brown"],
	["middle", "hair_f_bun", "", "brows_f_thin_arched", "tan", "black"],
]
const SKIN := {"pale": Color(.96,.84,.77), "medium": Color(.85,.65,.50), "tan": Color(.71,.50,.35), "dark": Color(.42,.28,.18)}
const HAIR := {"white": Color(.92,.92,.92), "red": Color(.78,.25,.10), "brown": Color(.42,.26,.14), "black": Color(.1,.08,.08), "grey": Color(.62,.62,.62)}


func _ready() -> void:
	_build_stage()
	_build_ui()
	_show(_chosen, _angle)
	if "--capture" in OS.get_cmdline_user_args(): _capture.call_deferred()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer, _title, Vector2(30,24), 30)
	_label(layer, _subtitle, Vector2(30,68), 20)
	_label(layer, _notes, Vector2(30,105), 17)
	_label(layer, _footer, Vector2(30,953), 18)
	var controls := HBoxContainer.new()
	controls.position = Vector2(30,145)
	controls.add_theme_constant_override("separation", 8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for mode in ["Personal room", "Communal table", "Communal 8x3", "Communal 8x4", "Seat guides", "Current spacing", "Chair fit"]:
		var button := Button.new()
		button.text = "Communal 8x2" if mode == "Communal table" else mode
		button.pressed.connect(func(): _show(mode, _angle))
		controls.add_child(button)
	var views := HBoxContainer.new()
	views.position = Vector2(30,187)
	views.add_theme_constant_override("separation", 8)
	views.visible = controls.visible
	layer.add_child(views)
	for angle in ["Three-quarter", "RTS", "Front", "Side", "Top"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_chosen, angle))
		views.add_child(button)
	var clearance := CheckButton.new()
	clearance.text = "Clearance"
	clearance.toggled.connect(func(on): _clearance = on; _envelopes.visible = on)
	views.add_child(clearance)
	var motion := CheckButton.new()
	motion.text = "Idle"
	motion.button_pressed = true
	motion.toggled.connect(func(on): _animate = on)
	views.add_child(motion)


func _prop(path: String, at: Vector3, yaw := 0.0) -> Node3D:
	var node := _part(_actors, path)
	node.position = at
	node.rotation_degrees.y = yaw
	return node


func _make_diner(at: Vector3, yaw: float, index: int) -> void:
	var style: Array = STYLES[index % STYLES.size()]
	var dwarf := Node3D.new()
	_actors.add_child(dwarf)
	dwarf.position = at
	dwarf.rotation_degrees.y = yaw
	var skin: Color = SKIN[style[4]]
	var hair: Color = HAIR[style[5]]
	var head := _part(dwarf, "res://dwarves/body/head_"+style[0]+".glb", skin)
	_part(head, "res://dwarves/body/eyes.glb", Color(.25,.55,.85))
	_part(head, "res://dwarves/hair/"+style[1]+".glb", hair)
	_part(head, "res://dwarves/eyebrows/"+style[3]+".glb", hair)
	if style[2] != "": _part(head, "res://dwarves/beards/"+style[2]+".glb", hair)
	var body := _part(dwarf, "res://dwarves/body/body_base.glb")
	body.position = Vector3(0,.25,-.125)
	head.position = body.position
	var hands: Array[Node3D] = []
	var feet: Array[Node3D] = []
	for mirror in [false, true]:
		var hand := _part(dwarf, "res://dwarves/body/hand.glb", skin, mirror)
		hand.position = Vector3(.10 if mirror else -.10, .75, 1.125)
		hands.append(hand)
		var foot := _part(dwarf, "res://dwarves/body/foot.glb", Color.WHITE, mirror)
		foot.position = Vector3(.125 if mirror else -.125, .125, .60)
		feet.append(foot)
	_seated.append({"node": dwarf, "head": head, "body": body, "hands": hands, "feet": feet, "phase": index*1.37})


func _seat(at: Vector3, yaw: float, index: int, current := false) -> void:
	_prop("res://reference/wooden_chair.glb" if current else "res://models/wide_chair.glb", at, yaw)
	_make_diner(at, yaw, index)


func _show(mode: String, angle: String) -> void:
	_chosen = mode
	_angle = angle
	_seated.clear()
	_table = null
	for child in _actors.get_children(): child.free()
	_envelopes = Node3D.new()
	_actors.add_child(_envelopes)
	_envelopes.visible = _clearance
	_title.text = "DEEPDRAFT / SEATED DINING STUDY"
	_footer.text = "Preview only  /  Original dwarf meshes at native scale  /  Each chair is a separate furniture item"
	var target := Vector3(0,1.1,.5)
	var size := 7.7
	if mode == "Personal room":
		_table = _prop("res://models/personal_table.glb", Vector3.ZERO)
		_seat(Vector3(0,0,2),180,0)
		_subtitle.text = "PERSONAL DINING / One dwarf, one table, one chair"
		_notes.text = "Table 2 × 2  /  Chair 2 × 2  /  Tabletop 1.75 high  /  Long-beard fit"
	elif mode.begins_with("Communal") or mode == "Seat guides":
		var depth := 2 if mode == "Communal table" else 3 if mode == "Communal 8x3" else 4
		var model := "communal_table" if depth == 2 else "communal_table_8x%d" % depth
		# Odd-depth furniture centers fall on half cells; all footprint edges
		# and chair origins must still align with the same whole-cell grid.
		var center := Vector3(0,0,.5 if depth == 3 else 0.0)
		_table = _prop("res://models/" + model + ".glb", center)
		var offset := depth*.5+1
		for i in range(3):
			for side in [1,-1]:
				var at := center + Vector3((i-1)*3,0,offset*side)
				var facing := 180.0 if side == 1 else 0.0
				if mode == "Seat guides":
					_guide(at, facing, i == 0 and side == 1)
				else:
					_seat(at, facing, i if side == 1 else i+3)
		_subtitle.text = "COMMUNAL DINING / Six dwarves around a long tavern table"
		_notes.text = "Table 8 × %d  /  Three seats per side  /  Seat centers 3 blocks apart  /  Independent 2 × 2 chairs" % depth
		if depth == 4:
			for side in [-1,1]:
				var at := center + Vector3(5*side,0,0)
				var facing := 90.0 if side == -1 else -90.0
				if mode == "Seat guides":
					_guide(at, facing, false)
				else:
					_seat(at, facing, 6 if side == -1 else 7)
			_subtitle.text = "COMMUNAL DINING / Eight dwarves around an 8 × 4 tavern table"
			_notes.text = "Three seats along each side + one at each end  /  Independent 2 × 2 chairs  /  Native dwarf scale"
		target = center + Vector3(0,1.25,0)
		size = 15 if depth == 4 else 14
		if mode == "Seat guides":
			_subtitle.text = "PLACEMENT CONCEPT / Eight chair positions around an 8 × 4 table"
			_notes.text = "Solid chair: already placed  /  Green chairs: available positions  /  Placement would snap and face the table"
			target.y = .8
	elif mode == "Current spacing":
		_prop("res://reference/wooden_table.glb", Vector3.ZERO)
		for i in range(2):
			_seat(Vector3(i-.5,0,1.5),180,i,true)
			_seat(Vector3(i-.5,0,-1.5),0,i+2,true)
		_subtitle.text = "CURRENT SPACING / Four dwarves on the original 1 × 1 chairs"
		_notes.text = "Diagnostic mock-up  /  Seat centers only 1 block apart  /  Overlapping heads and narrow seats"
		size = 9.5
		target.y = 1.5
		target.z = 0
	else:
		_seat(Vector3(-2,0,0),0,1,true)
		_seat(Vector3(2,0,0),0,0)
		_subtitle.text = "CHAIR FIT / Original chair at left, wider low-back prototype at right"
		_notes.text = "Same dwarf body dimensions  /  1 × 1 versus 2 × 2  /  Feet forward, torso on the seat, fists in dining pose"
		size = 9
		target.z = .25
	_build_grid(mode)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = size
	var elevation := 30.0
	var yaw := 24.0
	if mode == "Personal room": yaw = -145.0
	match angle:
		"RTS": elevation = 54.0
		"Front": elevation = 12.0; yaw = 0.0
		"Side": elevation = 10.0; yaw = 90.0
		"Top": elevation = 89.9; yaw = 0.0
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target + dir * 25
	_camera.look_at(target)
	_time = 0
	_pose(0)
	_draw_envelopes()


func _build_grid(mode: String) -> void:
	var half_width := 7 if mode.begins_with("Communal") or mode == "Seat guides" else 4
	for x in range(-half_width, half_width):
		for z in range(-5,6):
			var tile := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(.986,.014,.986)
			tile.mesh = mesh
			tile.position = Vector3(x+.5,.005,z+.5)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(.53,.57,.53) if (x+z)%2==0 else Color(.51,.55,.51)
			tile.material_override = material
			_actors.add_child(tile)


func _guide(at: Vector3, yaw: float, built: bool) -> void:
	var chair := _prop("res://models/wide_chair.glb", at, yaw)
	if built: return
	for mesh in chair.find_children("*", "MeshInstance3D", true, false):
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(.32,.8,.61,.38)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
	var marker := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(1.95,.014,1.95)
	marker.mesh = slab
	marker.position = at + Vector3(0,.02,0)
	var tint := StandardMaterial3D.new()
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = Color(.2,.65,.42,.3)
	marker.material_override = tint
	_actors.add_child(marker)


func _process(delta: float) -> void:
	if _animate:
		_time += delta
		_pose(_time)


func _pose(time: float) -> void:
	for diner in _seated:
		var t: float = time + diner.phase
		diner.head.position = Vector3(0,.25 + (sin(t*1.8)+1)*.012,-.125)
		diner.head.rotation.y = sin(t*.7)*.045
		for i in range(2):
			var hand: Node3D = diner.hands[i]
			hand.position.y = .75 + (sin(t*1.8+i)+1)*.009
			var foot: Node3D = diner.feet[i]
			foot.position.z = .60 + sin(t*1.5+i)*.035


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = child.global_transform * child.get_aabb()
		box = box.merge(part) if found else part
		found = true
	return box


func _draw_envelopes() -> void:
	for diner in _seated:
		var bounds := _bounds(diner.head)
		var mesh := BoxMesh.new()
		mesh.size = bounds.size + Vector3(.08,.08,.08)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = bounds.get_center()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(.25,.8,.7,.18) if _chosen != "Current spacing" else Color(.9,.25,.15,.22)
		instance.material_override = material
		_envelopes.add_child(instance)


func _check_layout() -> void:
	var collisions := 0
	var table_collisions := 0
	var smallest_gap := INF
	# Sample twelve seconds of idle in all four grid rotations. Head bounds
	# include the attached hair and beard; tabletop clearance matters too.
	for turn in range(4):
		_actors.rotation.y = turn * PI * .5
		for frame in range(180):
			_pose(float(frame)/15)
			var boxes: Array[AABB] = []
			for diner in _seated:
				var head_box := _bounds(diner.head)
				boxes.append(head_box)
				if is_instance_valid(_table):
					if head_box.intersects(_bounds(_table)): table_collisions += 1
					# The torso rests at seat height; palms rest above the tabletop.
					assert(is_equal_approx(_bounds(diner.body).position.y, .875))
					for hand in diner.hands: assert(_bounds(hand).position.y >= 1.749)
			for i in range(boxes.size()):
				for j in range(i+1,boxes.size()):
					if boxes[i].intersects(boxes[j]): collisions += 1
					var gap := maxf(maxf(boxes[j].position.x-boxes[i].end.x, boxes[i].position.x-boxes[j].end.x), maxf(boxes[j].position.z-boxes[i].end.z, boxes[i].position.z-boxes[j].end.z))
					smallest_gap = minf(smallest_gap,gap)
	_actors.rotation.y = 0
	_report.append({"layout": _chosen, "diners": _seated.size(), "rotations": 4, "idle_samples_per_rotation": 180, "head_overlap_samples": collisions, "head_table_overlap_samples": table_collisions, "min_axis_gap": snappedf(smallest_gap,.001) if is_finite(smallest_gap) else null})
	if _chosen == "Communal 8x4": assert(_seated.size() == 8, "Communal table needs six side seats and two end seats")
	assert(table_collisions == 0, "Prototype hair/beard intersects the table")
	if _chosen.begins_with("Communal"): assert(collisions == 0, "Prototype heads overlap")
	if _chosen == "Current spacing": assert(collisions > 0, "Diagnostic should reproduce crowding")
	_pose(0)


func _capture() -> void:
	_animate = false
	for spec in [["Personal room","Three-quarter","personal"], ["Personal room","Side","personal_side"],
		["Personal room","RTS","personal_rts"], ["Communal table","Three-quarter","communal"],
		["Communal table","RTS","communal_rts"], ["Communal table","Top","communal_top"],
		["Communal 8x3","Three-quarter","communal_8x3"], ["Communal 8x3","RTS","communal_8x3_rts"],
		["Communal 8x4","Three-quarter","communal_8x4"], ["Communal 8x4","RTS","communal_8x4_rts"],
		["Communal 8x4","Top","communal_8x4_top"], ["Seat guides","RTS","seat_guides"],
		["Current spacing","RTS","current_crowding"], ["Chair fit","Three-quarter","chair_fit"]]:
		_show(spec[0],spec[1])
		_check_layout()
		await _shot(spec[2])
	var file := FileAccess.open("res://clearance_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report,"  "))
	_show("Communal 8x4", "Three-quarter")
	for frame in range(48):
		_pose(float(frame)/12)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://renders/idle_%03d.png" % frame)
	print("SEATING_STUDY_OK: personal table, communal widths, eight-seat head/table clearance, snap-guide concept")
	get_tree().quit(0)
