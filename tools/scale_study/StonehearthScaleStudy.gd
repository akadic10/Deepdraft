extends "res://tools/scale_study/ScaleStudy.gd"

## Reference meshes are generated locally from the user's Stonehearth directory.
## This owner loads its measurement report; no production registry consumes it.
const SH_OUT := "res://tmp/stonehearth_scale_20261013/"
const SH_REF := SH_OUT+"reference/"
var reference_data: Dictionary
var pages: Dictionary = {}
var match_heights := false
var comparison_nodes: Array[Dictionary] = []


func _build_lineup() -> void:
	reference_data=JSON.parse_string(FileAccess.get_file_as_string(SH_REF+"measurements.json"))
	# Replace the inherited ruler platform with a platform sized for each page.
	for child in lineup.get_children():
		lineup.remove_child(child); child.queue_free()
	for page in ["People","Wildlife","Trees"]:
		var root := Node3D.new()
		lineup.add_child(root)
		pages[page]=root
	_build_people()
	_build_wildlife()
	_build_trees()


func _platform(page: String, width: float, height: int) -> void:
	var root: Node3D=pages[page]
	_box(root,Vector3(116,20.5,40),Vector3(width,1,10),Color("667563"))
	for y in range(height+1):
		if height>5 and y%5!=0: continue
		_box(root,Vector3(116,21+y,37),Vector3(width,.08 if height>5 else .035,.025),Color("97ABA6"))
		_label_at(str(y),Vector3(115-width/2,21+y,37),root,true)


func _build_people() -> void:
	_platform("People",21,4)
	var root: Node3D=pages.People
	for i in 4: _box(root,Vector3(107,21.5+i,39),Vector3.ONE,Color("89939C") if i%2==0 else Color("747F89"))
	_label_at("4 blocks",Vector3(107,20.2,42),root)
	var dwarf := _dwarf(root,Vector3(112,21,40),0)
	dwarf.rotation_degrees.y=0
	comparison_nodes.append({"node":dwarf,"key":"hearthling","label":"Deepdraft dwarf"})
	_label_at("Deepdraft\n3.32 high",Vector3(112,20.2,42),root)
	_reference_model(root,"hearthling",Vector3(117,21,40),0)
	_label_at("Stonehearth\n3.30 high",Vector3(117,20.2,42),root)
	_prop(root,"door",Vector3(123,21,40))
	_label_at("Deepdraft door\n2-wide opening",Vector3(123,20.2,42),root)


func _build_wildlife() -> void:
	_platform("Wildlife",36,4)
	var root: Node3D=pages.Wildlife
	var x := 102.0
	for species in ["deer","wolf","rabbit"]:
		var actor := _animal(root,species,Vector3(x,21,40))
		actor.rotation_degrees.y=90
		comparison_nodes.append({"node":actor,"key":species,"label":"Deepdraft "+species})
		_label_at("DD "+species,Vector3(x,20.2,42),root)
		_reference_model(root,species,Vector3(x+5,21,40),-90)
		_label_at("SH "+species,Vector3(x+5,20.2,42),root)
		x+=11.5


func _build_trees() -> void:
	_platform("Trees",76,30)
	var root: Node3D=pages.Trees
	for spec in [["pine_mature",88.0],["oak_mature",110.0],["pine_ancient",139.0]]:
		var key: String=spec[0]
		var species: String=key.split("_")[0]
		var x: float=spec[1]
		var tree := _model(root,"res://assets/models/flora/trees/"+species+"/"+key+".glb",Vector3(x,21,40))
		comparison_nodes.append({"node":tree,"key":key,"label":"Deepdraft "+key})
		_label_at("DD "+key.replace("_"," "),Vector3(x,20.2,42),root)
		_reference_model(root,key,Vector3(x+11,21,40),0)
		_label_at("SH "+key.replace("_"," ").replace("mature","medium").replace("ancient","large"),Vector3(x+11,20.2,42),root)


func _reference_model(parent: Node3D, key: String, at: Vector3, facing: float) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(ProjectSettings.globalize_path(SH_REF+key+".glb"),state)
	assert(result==OK,"Generate Stonehearth review meshes with the launcher first")
	var node: Node3D=document.generate_scene(state)
	parent.add_child(node)
	node.position=at
	node.rotation_degrees.y=facing
	for mesh in node.find_children("*","MeshInstance3D",true,false): mesh.material_override=floor_material
	specimens.append({"node":node,"family":"reference","id":"SH "+key,"stage":"reference","key":key})


func _measure() -> void:
	super._measure()
	for entry in comparison_nodes:
		var box := _bounds(entry.node)
		report.measurements[entry.label]={"height":snappedf(box.size.y,.001),"width":snappedf(box.size.x,.001),"depth":snappedf(box.size.z,.001)}


func _build_ui() -> void:
	get_window().title="Deepdraft / Stonehearth — Scale comparison"
	var layer := CanvasLayer.new(); add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left=18; panel.offset_right=-18; panel.offset_top=14
	panel.add_theme_stylebox_override("panel",UITheme.hearth_panel(true))
	layer.add_child(panel)
	var column := VBoxContainer.new(); panel.add_child(column)
	var title := Label.new()
	title.text="DEEPDRAFT / STONEHEARTH  ·  ONE SHARED BLOCK RULER"
	UITheme.apply_title(title,23); column.add_child(title)
	var row := HBoxContainer.new(); column.add_child(row)
	for value in ["People","Wildlife","Trees","Settlement"]: _button(value,func(): _select_view(value),row)
	_button("1 · Current",func(): _preset("A"),row)
	_button("2 · SH heights",func(): _preset("B"),row)
	_button("Light",func(): _set_light("Dusk" if time_of_day=="Day" else "Day"); _refresh_ui(),row)
	_button("Reset view",func(): _select_view(view),row)
	caption=Label.new(); caption.add_theme_font_size_override("font_size",15); column.add_child(caption)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left=18; bottom.offset_right=-18; bottom.offset_top=-103; bottom.offset_bottom=-14
	bottom.add_theme_stylebox_override("panel",UITheme.hearth_panel(true)); layer.add_child(bottom)
	var bottom_column := VBoxContainer.new(); bottom.add_child(bottom_column)
	detail=Label.new(); bottom_column.add_child(detail)
	footer=Label.new(); bottom_column.add_child(footer)
	footer.text="RMB orbit · Wheel zoom · 1 current / 2 SH heights · Esc exit   |   Static reference poses; production sizes and saves unchanged"
	footer.add_theme_font_size_override("font_size",13)
	footer.add_theme_color_override("font_color",UITheme.HEARTH_MUTED)
	for spec in labels:
		var label := Label.new(); label.text=spec.text
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",15 if spec.small else 16 if spec.parent==pages.Trees else 18)
		label.add_theme_color_override("font_color",Color("E8DBC0"))
		label.add_theme_color_override("font_shadow_color",Color("152120"))
		label.add_theme_constant_override("shadow_offset_x",2); label.add_theme_constant_override("shadow_offset_y",2)
		layer.add_child(label); spec["label"]=label
	# Base label updating expects a reference panel; this viewer uses direct models.
	reference_panel=PanelContainer.new(); layer.add_child(reference_panel); reference_panel.hide()


func _select_view(value: String) -> void:
	view="People" if value=="Lineup" else value
	lineup.visible=view!="Settlement"
	settlement.visible=view=="Settlement"
	terrain.visible=view=="Settlement"
	for page in pages: pages[page].visible=page==view
	match view:
		"People": target=Vector3(116,22.5,40); yaw=0; pitch=0; zoom=16
		"Wildlife": target=Vector3(116,22.4,40); yaw=0; pitch=0; zoom=26
		"Trees": target=Vector3(116,34,40); yaw=0; pitch=0; zoom=53
		"Settlement": target=Vector3(48,26,47); yaw=-28; pitch=40; zoom=49
	_update_camera(); _refresh_ui()


func _preset(id: String) -> void:
	match_heights=id=="B"
	for entry in comparison_nodes:
		var height := _bounds(entry.node).size.y
		var factor: float=reference_data.models[entry.key].height/height if match_heights else 1.0
		entry.node.scale=Vector3.ONE*factor
	for spec in specimens:
		if spec.stage!="settlement": continue
		var key := ""
		if spec.family=="dwarves": key="hearthling"
		elif spec.family=="animals" and spec.id.to_lower() in ["deer","wolf","rabbit"]: key=spec.id.to_lower()
		elif spec.family=="trees": key=spec.id.split("/")[1]
		if reference_data.models.has(key):
			var factor: float=reference_data.models[key].height/_bounds(spec.node).size.y if match_heights else 1.0
			spec.node.scale=Vector3.ONE*factor
	_refresh_ui()


func _refresh_ui() -> void:
	if caption==null: return
	caption.text="%s · %s · %s" % [view,"Deepdraft matched to SH height (uniform scale only)" if match_heights else "Actual source sizes",time_of_day]
	buttons.Light.text="Light: "+time_of_day
	for spec in labels:
		if spec.text.begins_with("Deepdraft\n") and spec.has("label"):
			spec.label.text="Deepdraft\n%s high" % ("3.30" if match_heights else "3.32")
	match view:
		"People": detail.text="Source sizes: dwarf 3.32 high / 2.60 hand span   ·   Hearthling 3.30 high / 1.90 hand span\nNearly equal height; Deepdraft has a broader torso and head. SH sample wears its worker outfit and ordinary hair."
		"Wildlife": detail.text="Source heights DD / SH: deer 3.77 / 3.60 · wolf 1.84 / 2.40 · rabbit 1.47 / 1.00\nDD = Deepdraft · SH = Stonehearth · Static authored SH poses; rabbit ear posture differs. No ordinary duck counterpart."
		"Trees": detail.text="Source heights DD / SH: mature pine 20 / 20 · mature oak 17 / 16 · ancient pine 27 / 27\nSH medium and large stages are paired by stature, not identical stage names. Default first model variant shown."
		"Settlement": detail.text="Height trial: dwarf ~99% · deer 96% · wolf 130% · rabbit 68% · mature oak 94% · mature pine 100%\nOur forms scaled to SH heights, not SH anatomy. Duck, furniture and oak sapling stay current."


func _process(_delta: float) -> void:
	if not ready_for_review: return
	for spec in labels:
		var label: Label=spec.label
		label.visible=spec.parent.is_visible_in_tree()
		if label.visible:
			label.size=Vector2(158,48)
			label.position=camera.unproject_position(spec.at)-Vector2(79,15 if spec.small else 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in [KEY_R,KEY_3]: return
	super._unhandled_input(event)


func _capture_all() -> void:
	var fingerprint: String=terrain.fingerprint()
	for spec in specimens:
		if spec.family!="reference": continue
		var box := _bounds(spec.node)
		var expected: Dictionary=reference_data.models[spec.key]
		_check(absf(box.size.y-expected.height)<.001,"SH mesh height: "+spec.key)
		_check(absf(box.size.x-expected.width)<.001,"SH mesh width: "+spec.key)
		_check(absf(box.size.z-expected.depth)<.001,"SH mesh depth: "+spec.key)
		_check(absf(box.position.y)<.001,"SH soles on shared ground: "+spec.key)
	for page in ["People","Wildlife","Trees","Settlement"]:
		_select_view(page); buttons["1 · Current"].pressed.emit()
		await _capture(page.to_lower()+"_current")
		var fixed_camera := camera.global_transform
		var fixed_size := camera.size
		buttons["2 · SH heights"].pressed.emit()
		_check(camera.global_transform.is_equal_approx(fixed_camera) and camera.size==fixed_size,"Height trial retains camera: "+page)
		await _capture(page.to_lower()+"_sh_heights")
		for entry in comparison_nodes:
			var displayed_height: float=_bounds(entry.node).size.y*entry.node.scale.y
			_check(absf(displayed_height-reference_data.models[entry.key].height)<.001,"Height trial matches source: "+entry.label)
	buttons["1 · Current"].pressed.emit(); _select_view("People")
	for entry in comparison_nodes: _check(entry.node.scale.is_equal_approx(Vector3.ONE),"Reset dimensions: "+entry.label)
	_check(terrain.fingerprint()==fingerprint,"Reference comparison preserves world blocks")
	_check(SaveManager._save_directory_path=="user://scale_study" and not SaveManager.is_processing(),"Save isolation")
	_check(reference_data.source_unchanged,"Source export verified read-only")
	report["checks"]=checks; report["failures"]=failures; report["passed"]=failures.is_empty()
	report["source_measurements"]="reference/measurements.json"
	FileAccess.open(SH_OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("STONEHEARTH_SCALE_OK" if failures.is_empty() else "STONEHEARTH_SCALE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture(id: String) -> void:
	for i in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(SH_OUT+id+".png")==OK,"Capture "+id)
	report.captures[id]={"camera_size":camera.size,"camera_position":str(camera.position),"camera_rotation":str(camera.rotation),"match_sh_heights":match_heights}
