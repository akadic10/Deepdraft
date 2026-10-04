extends "TavernRedesignPreview.gd"

func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("Counter","Three-quarter")
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
	for mode in ["Counter","Dwarf scale","Tavern comparison","Storage context"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(mode,_angle))
		controls.add_child(button)
	for angle in ["Three-quarter","RTS","Rear"]:
		var button := Button.new()
		button.text = angle
		button.pressed.connect(func(): _show(_tavern_mode,angle))
		controls.add_child(button)
	_label(layer,_footer,Vector2.ZERO,17)
	for i in range(2):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(layer,label,Vector2.ZERO,22)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   STONE TRADE COUNTER"
	_subtitle.text = "Dressed-stone slab · broad supports · iron edging · inset geometric carving"
	_footer.text = "8 voxels per block · 2 × 1 footprint / 2 blocks tall · Placeable furniture; merchant trading is a future system"
	var target := Vector3(0,1,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.9
	var elevation := 25.0 if angle=="Three-quarter" else 50.0
	var yaw := 30.0 if angle!="Rear" else 205.0
	if mode=="Dwarf scale":
		_prop("res://models/trade_counter.glb",Vector3(1.55,0,.35),15)
		_dwarf(_actors,Vector3(-1.1,0,0),15)
		_prop("res://context/packed_furniture.glb",Vector3(.2,0,1.8))
		_camera.size = 7.8
		target = Vector3(.3,1.35,0)
		yaw = 0
		_subtitle.text = "Counter 2 blocks tall · dwarf 3.375 blocks · shared packed crate at actual scale"
	elif mode=="Tavern comparison":
		_prop("res://context/tavern_bar.glb",Vector3(-1.9,0,0),15)
		_prop("res://models/trade_counter.glb",Vector3(1.9,0,0),15)
		_camera.size = 8
		yaw = 0
		_labels[0].text = "TAVERN BAR / OAK"
		_labels[1].text = "TRADE COUNTER / STONE"
		_subtitle.text = "Two distinct furniture roles · identical 2 × 1 footprints · actual asset sizes"
	elif mode=="Storage context":
		_prop("res://models/trade_counter.glb",Vector3.ZERO)
		_prop("res://context/storage_crate.glb",Vector3(2.1,0,.1),15)
		_prop("res://context/barrel.glb",Vector3(3.3,0,0),-15)
		_dwarf(_actors,Vector3(-1.8,0,-1.6),35)
		_camera.size = 10
		target = Vector3(.7,1,0)
		elevation = 42
		_subtitle.text = "Counter with upgraded storage and dwarf · actual asset sizes"
	else:
		_prop("res://models/trade_counter.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Counter","Three-quarter","counter"],["Counter","RTS","counter_rts"],["Counter","Rear","counter_rear"],
		["Dwarf scale","Three-quarter","dwarf_scale"],["Dwarf scale","RTS","dwarf_scale_rts"],
		["Tavern comparison","Three-quarter","tavern_comparison"],["Storage context","RTS","storage_context"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("TRADE_COUNTER_REVIEW_OK")
	get_tree().quit(0)
