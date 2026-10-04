extends "TreeRedesignPreview.gd"

var _count := 3
var _species := "oak"
var _season := "summer"
var _selection := "Growth stages"
var _spacing := 29.0
var _anchors: Array[Vector3] = []


func _ready() -> void:
	_build_stage()
	_build_ui()
	_show("oak","summer","Ancient forest")
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer,_title,Vector2(28,20),28)
	_label(layer,_subtitle,Vector2(28,58),19)
	var controls := HBoxContainer.new()
	controls.position = Vector2(28,96)
	controls.add_theme_constant_override("separation",8)
	controls.visible = not "--capture" in OS.get_cmdline_user_args()
	layer.add_child(controls)
	for species in ["oak","pine","apple","juniper"]:
		var button := Button.new()
		button.text = species.capitalize()
		button.pressed.connect(func(): _show(species,_season,_selection))
		controls.add_child(button)
	for season in ["spring","summer","autumn","autumn_fruiting","winter"]:
		var button := Button.new()
		button.text = season
		button.pressed.connect(func(): _show(_species,season,_selection))
		controls.add_child(button)
	for mode in ["Growth stages","Mature variants","Ancient variants","Ancient forest"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(func(): _show(_species,_season,mode))
		controls.add_child(button)
	_label(layer,_footer,Vector2.ZERO,17)
	for i in range(4):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(layer,label,Vector2.ZERO,22)
		_labels.append(label)
	get_viewport().size_changed.connect(_place_labels)


func _model(species: String, stage: String, season: String, variant: int, at: Vector3) -> void:
	var effective := season
	if species in ["pine","juniper"] and season != "winter":
		effective = "summer"
	if species == "apple" and stage == "sapling" and season == "autumn_fruiting":
		effective = "autumn"
	if species == "oak" and season == "autumn_fruiting":
		effective = "autumn"
	var suffix := ("" if effective == "summer" else "_"+effective)+("" if variant == 1 else "_"+str(variant))
	var group := Node3D.new()
	_actors.add_child(group)
	_trees.append(group)
	group.position = at
	group.rotation_degrees.y = 25
	_part(group,"res://models/"+species+"/"+species+"_"+stage+suffix+".glb")
	_dwarf(_actors,at+Vector3(9 if stage == "ancient" else 6,0,8))
	_anchors.append(at)


func _show(species: String, season: String, selection: String) -> void:
	_species = species; _season = season; _selection = selection
	_trees.clear();_anchors.clear()
	for child in _actors.get_children():
		child.free()
	for label in _labels:
		label.text = ""
	_count = 4 if selection == "Ancient forest" else (2 if species == "juniper" and selection != "Growth stages" else 3)
	_spacing = 29 if species in ["oak","apple"] or selection == "Ancient forest" else 23
	_title.text = "DEEPDRAFT   /   COMPLETE FOREST"
	_subtitle.text = species.capitalize()+" · "+selection+" · "+season.replace("_"," ")+" · Same world scale across the lineup"
	_footer.text = "1 voxel per block · Dwarfs at actual 3.375-block height · Matching seasonal structures and variant order"
	for i in range(_count):
		var sp: String = ["oak","pine","apple","juniper"][i] if selection == "Ancient forest" else species
		var stage: String = ["sapling","mature","ancient"][i] if selection == "Growth stages" else ("mature" if selection == "Mature variants" else "ancient")
		var variant := i+1 if selection in ["Mature variants","Ancient variants"] else 1
		_model(sp,stage,season,variant,Vector3((i-(_count-1)*.5)*_spacing,0,0))
		_labels[i].text = (sp.to_upper()+" / "+stage) if selection == "Ancient forest" else stage.to_upper()+(" / variant "+str(variant) if selection != "Growth stages" else "")
	if selection == "Ancient forest":
		_subtitle.text = "Ancient oak, pine, apple and juniper · "+season.capitalize()+" · Redesigned heavy branches and coherent crowns"
	_set_view(_view)


func _set_view(view_name: String) -> void:
	_view = view_name
	var elevation := 50.0 if view_name == "RTS" else 28.0
	var target := Vector3(0,11,0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = maxf(43,_count*_spacing*.66)
	_camera.position = target+Vector3(0,sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation)))*110
	_camera.look_at(target)
	for tree in _trees:
		tree.rotation_degrees.y = 145 if view_name == "Rear" else 25
	_place_labels()


func _place_labels() -> void:
	var size := get_viewport().get_visible_rect().size
	for i in range(_labels.size()):
		_labels[i].position = Vector2(size.x*(i+.5)/_count-210,size.y-94)
		_labels[i].size = Vector2(420,30)
	_footer.position = Vector2(28,size.y-42)


func _capture() -> void:
	for season in ["summer","winter"]:
		_show("oak",season,"Ancient forest")
		await _shot("ancient_forest_"+season)
	for species in ["oak","pine","apple","juniper"]:
		var seasons: Array = ["summer","winter"] if species in ["pine","juniper"] else ["spring","summer","autumn","winter"]
		if species == "apple":
			seasons.append("autumn_fruiting")
		for season in seasons:
			_show(species,season,"Growth stages")
			await _shot(species+"_ages_"+season)
			for selection in ["Mature variants","Ancient variants"]:
				_show(species,season,selection)
				await _shot(species+"_"+selection.to_lower().replace(" ","_")+"_"+season)
		_show(species,"summer","Growth stages")
		_set_view("RTS")
		await _shot(species+"_ages_rts")
		_set_view("Rear")
		await _shot(species+"_ages_rear")
		_set_view("Three-quarter")
	print("FOREST_ROSTER_REVIEW_OK")
	get_tree().quit(0)
