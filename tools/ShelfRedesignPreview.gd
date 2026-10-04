extends "TavernRedesignPreview.gd"

const ITEM_LAYOUT = preload("res://scripts/components/StorageItemLayout.gd")
var _storage: Dictionary

func _ready() -> void:
	_storage = JSON.parse_string(FileAccess.get_file_as_string("res://review_storage.json"))
	_build_stage()
	_build_ui()
	_show("Shelf","Three-quarter")
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
	for mode in ["Shelf","Stocked","Crates","Comparison","Dwarf scale","Storage set"]:
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

func _stocked(at: Vector3,turn: float = 0,crates: bool = false) -> Node3D:
	var rack := _prop("res://models/storage_shelf.glb",at,turn)
	var items := ["packed_furniture","copper_ore","iron_ore","rough_stone"]
	for i in range(8):
		var item := _part(rack,"res://context/"+("packed_furniture" if crates else items[i%4])+".glb")
		var anchor: Array = _storage.anchors[i]
		item.position = Vector3(anchor[0]-.5,anchor[1],anchor[2]-.5)
		item.scale = Vector3.ONE*float(_storage.anchor_scale)
		item.rotation.y = float(i*2654435761%628)/100.0
		var size: Array = _storage.anchor_max_size
		ITEM_LAYOUT.fit(item,Vector3(size[0],size[1],size[2]),float(_storage.anchor_scale))
	return rack

func _show(mode: String,angle: String) -> void:
	_tavern_mode = mode
	_angle = angle
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_title.text = "DEEPDRAFT   /   OPEN OAK STORAGE SHELF"
	_subtitle.text = "Oak uprights · iron corner fittings · two plank decks · open crown for visible storage"
	_footer.text = "8 voxels per block · 1 × 1 footprint / 2 blocks tall · 8 visible slots, four per level"
	var target := Vector3(0,1,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.25
	var elevation := 25.0 if angle=="Three-quarter" else 50.0
	var yaw := 30.0 if angle!="Rear" else 205.0
	if mode=="Comparison":
		_prop("res://reference/storage_shelf.glb",Vector3(-1.2,0,0),15)
		_prop("res://models/storage_shelf.glb",Vector3(1.2,0,0),15)
		_camera.size = 5.8
		yaw = 0
		_labels[0].text = "ORIGINAL / SHELF"
		_labels[1].text = "REDESIGN / SHELF"
		_subtitle.text = "Identical footprint, height and lighting · original retains its in-game color interpretation"
	elif mode=="Stocked" or mode=="Crates":
		_stocked(Vector3.ZERO,0,mode=="Crates")
		_subtitle.text = "Eight example stored items · actual item meshes fitted to the live shelf slots · "+angle
	elif mode=="Dwarf scale":
		_stocked(Vector3(1.25,0,.2),15)
		_dwarf(_actors,Vector3(-1.35,0,0),10)
		_camera.size = 7.5
		target = Vector3(0,1.5,0)
		yaw = 0
		_subtitle.text = "Standing dwarf and stocked shelf · native asset sizes · contents shown at shelf display scale"
	elif mode=="Storage set":
		_stocked(Vector3(-1.6,0,-.4),15)
		_stocked(Vector3(-.1,0,-.4),15,true)
		_prop("res://context/storage_crate.glb",Vector3(1.4,0,.5),15)
		_prop("res://context/barrel.glb",Vector3(2.6,0,.4),15)
		_dwarf(_actors,Vector3(-2.3,0,1.5),-15)
		_camera.size = 8
		target = Vector3(.2,1,.3)
		yaw = 0
		_subtitle.text = "Independent shelves, chest and barrel · matching oak and iron · examples of stored contents"
	else:
		_prop("res://models/storage_shelf.glb",Vector3.ZERO)
		_subtitle.text += " · "+angle
	var dir := Vector3(sin(deg_to_rad(yaw))*cos(deg_to_rad(elevation)),sin(deg_to_rad(elevation)),cos(deg_to_rad(yaw))*cos(deg_to_rad(elevation)))
	_camera.position = target+dir*15
	_camera.look_at(target)
	_place_labels()

func _capture() -> void:
	for spec in [["Comparison","Three-quarter","comparison"],["Shelf","Three-quarter","shelf"],
		["Shelf","RTS","shelf_rts"],["Shelf","Rear","shelf_rear"],
		["Stocked","Three-quarter","stocked"],["Stocked","RTS","stocked_rts"],
		["Crates","Three-quarter","crates"],["Dwarf scale","Three-quarter","dwarf_scale"],
		["Storage set","RTS","storage_set"]]:
		_show(spec[0],spec[1])
		await _shot(spec[2])
	print("SHELF_REDESIGN_REVIEW_OK")
	get_tree().quit(0)
