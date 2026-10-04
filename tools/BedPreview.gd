extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Bed","Three-quarter")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer,_title,Vector2(28,20),28)
	_label(layer,_subtitle,Vector2(28,61),19)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,102)
	controls.add_theme_constant_override("separation",8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for mode in ["Bed","Standing scale","Reclining scale","Bedroom"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","RTS","Rear","Top"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_tavern_mode,angle))
		controls.add_child(button)
	_label(layer,_footer,Vector2.ZERO,17)
	get_viewport().size_changed.connect(_place_labels)

func _reclining_dwarf() -> void:
	# Static fit study using the shipping parts, not a gameplay sleep animation.
	var pose := Node3D.new()
	_actors.add_child(pose)
	pose.basis = Basis(Vector3(0,0,-1),Vector3(-1,0,0),Vector3(0,1,0))
	pose.position = Vector3(1.75,1.75,0)
	var skin := Color(.85,.65,.50)
	var hair := Color(.42,.26,.14)
	_part(pose,"res://dwarves/head_adult.glb",skin)
	_part(pose,"res://dwarves/eyes.glb",Color(.25,.55,.85))
	_part(pose,"res://dwarves/brows_m_arched.glb",hair)
	_part(pose,"res://dwarves/hair_m_short_back.glb",hair)
	_part(pose,"res://dwarves/beard_short_trimmed.glb",hair)
	var body := _part(pose,"res://dwarves/body_base.glb")
	body.position.z = -.35
	for mirror in [false,true]:
		var hand := _part(pose,"res://dwarves/hand.glb",skin,mirror)
		hand.position.x = .625 if mirror else -.625
		hand.position.z = -.1
		var foot := _part(pose,"res://dwarves/foot.glb",Color.WHITE,mirror)
		foot.position.z = -.15

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	_title.text = "DEEPDRAFT   /   DWARVEN OAK BED"
	_subtitle.text = "Heavy oak frame · linen-covered straw mattress · broad pillow · folded wool blanket"
	_footer.text = "8 voxels per block · 4 × 2 footprint · 1-block mattress / 2-block headboard · Independent furniture item"
	var target := Vector3(0,.8,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 6.4
	var elevation := 30.0
	var yaw := 38.0
	if angle=="RTS":
		elevation = 52
	elif angle=="Rear":
		yaw = 235
	elif angle=="Top":
		elevation = 89.9
		yaw = 0
	if mode=="Standing scale":
		_prop("res://models/dwarf_bunk.glb",Vector3(1.15,0,.3))
		_dwarf(_actors,Vector3(-2.4,0,0),10)
		_prop("res://context/packed_furniture.glb",Vector3(-1.6,0,1.8))
		_camera.size = 9.7
		target = Vector3(.05,1.3,0)
		yaw = 0
		_subtitle.text = "Actual asset sizes · standing dwarf 3.375 blocks tall · one separately buildable bed"
	elif mode=="Reclining scale":
		_prop("res://models/dwarf_bunk.glb",Vector3.ZERO)
		_reclining_dwarf()
		_camera.size = 6.7
		elevation = 60 if angle!="Top" else 89.9
		yaw = 0 if angle=="Top" else 25
		_subtitle.text = "Static reclining fit study using full-size dwarf parts · preview pose only; sleeping behavior is future work"
	elif mode=="Bedroom":
		_prop("res://models/dwarf_bunk.glb",Vector3.ZERO)
		_prop("res://context/storage_crate.glb",Vector3(3,0,0),90)
		_prop("res://context/wooden_chair.glb",Vector3(-2.5,0,2),90)
		_dwarf(_actors,Vector3(1.3,0,3.1),20)
		_camera.size = 10
		target = Vector3(.3,.9,.8)
		elevation = 50
		_subtitle.text = "Example room furnishings · bed, chest and chair are independently built and placed"
	else:
		_prop("res://models/dwarf_bunk.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Bed","Three-quarter","bed"],["Bed","RTS","bed_rts"],["Bed","Rear","bed_rear"],
		["Standing scale","Three-quarter","standing_scale"],["Reclining scale","RTS","reclining_scale"],
		["Reclining scale","Top","reclining_top"],["Bedroom","RTS","bedroom"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("BED_REVIEW_OK")
	get_tree().quit(0)
