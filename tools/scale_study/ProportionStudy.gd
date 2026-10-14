extends "res://tools/scale_study/ScaleStudy.gd"

## Owns the study-only profile data. Production assets and registries stay intact.
const REVIEW_OUT := "res://tmp/proportion_study_20261013/"
const REF := "res://tmp/stonehearth_scale_20261013/reference/"
var profiles: Dictionary
var pages: Dictionary = {}
var trials: Array[Dictionary] = []
var props: Array[Node3D] = []
var references: Array[Dictionary] = []
var rulers: Array[Node3D] = []
var angle := "Front"
var choice := 3
const SETTLEMENT_CHOICES := [[0,0],[1,1],[2,2],[1,2]]
var _installed := {} # Production seating's optional look-at query.


func _build_lineup() -> void:
	profiles=JSON.parse_string(FileAccess.get_file_as_string("res://tools/scale_study/proportion_trials.json"))
	for child in lineup.get_children(): lineup.remove_child(child); child.queue_free()
	for page in ["Dwarf A","Dwarf B","Wolves"]:
		var root := Node3D.new(); lineup.add_child(root); pages[page]=root
		_box(root,Vector3(116,20.5,40),Vector3(27,1,11),Color("667563"))
		var ruler := Node3D.new(); root.add_child(ruler); rulers.append(ruler)
		for y in 5:
			_box(ruler,Vector3(116,21+y,37),Vector3(27,.04,.025),Color("97ABA6"))
			_label_at(str(y),Vector3(102,21+y,37),ruler,true)
	for page in ["Dwarf A","Dwarf B"]:
		for i in 3:
			var at := Vector3(107.5+i*5.5,21,40)
			var dwarf := _dwarf(pages[page],at,0 if page=="Dwarf A" else 1)
			dwarf.rotation=Vector3.ZERO
			var entry := {"node":dwarf,"family":"dwarf","variant":i,"page":page,"base":at}
			_make_props(entry,pages[page])
			trials.append(entry)
			_label_at(profiles.dwarves[i].label,at+Vector3(0,-.9,2),pages[page])
		_reference(pages[page],"hearthling",Vector3(124,21,40),0)
		_label_at("SH reference\n3.30 high",Vector3(124,20.1,42),pages[page])
	for i in 3:
		var at := Vector3(107.5+i*5.5,21,40)
		var wolf := _animal(pages.Wolves,"wolf",at)
		wolf.rotation_degrees.y=90
		trials.append({"node":wolf,"family":"wolf","variant":i,"page":"Wolves","base":at})
		_label_at(profiles.wolves[i].label,at+Vector3(0,-.9,2),pages.Wolves)
	_reference(pages.Wolves,"wolf",Vector3(124,21,40),-90)
	_label_at("SH reference\n2.40 high",Vector3(124,20.1,42),pages.Wolves)
	# The inherited settlement gives an unchanged unit-grid and pine-height context.
	for spec in specimens:
		if spec.node.get_parent()!=settlement: continue
		if spec.family=="dwarves" or (spec.family=="animals" and spec.id=="Wolf"):
			trials.append({"node":spec.node,"family":"dwarf" if spec.family=="dwarves" else "wolf","variant":choice,"page":"Settlement","base":spec.node.position})
	pose="Stand"
	_apply_review_pose()


func _make_props(entry: Dictionary, parent: Node3D) -> void:
	for pair in [["seat","wooden_chair"],["bed","log_bed"]]:
		var piece := InstalledFurnitureComponent.new()
		piece.def=source.get_defs()["base:furniture:"+pair[1]]
		piece.node=_prop(parent,pair[1],entry.base)
		piece.node.rotation_degrees.y=-90 if pair[0]=="bed" else 0
		entry[pair[0]]=piece
		props.append(piece.node)
	var cargo: Node3D=load("res://assets/models/items/stone/rough_stone.glb").instantiate()
	entry.node.add_child(cargo)
	entry.node._carry_pose._material(cargo)
	entry["cargo"]=cargo
	props.append(cargo)


func _reference(parent: Node3D, key: String, at: Vector3, facing: float) -> void:
	var document := GLTFDocument.new(); var state := GLTFState.new()
	assert(document.append_from_file(ProjectSettings.globalize_path(REF+key+".glb"),state)==OK)
	var node: Node3D=document.generate_scene(state)
	parent.add_child(node); node.position=at; node.rotation_degrees.y=facing
	references.append({"node":node,"facing":facing})
	for mesh in node.find_children("*","MeshInstance3D",true,false): mesh.material_override=floor_material


func _apply_review_pose() -> void:
	for prop in props: prop.hide()
	for entry in trials:
		var actor: Node3D=entry.node
		var variant: int=SETTLEMENT_CHOICES[choice][0 if entry.family=="dwarf" else 1] if entry.page=="Settlement" else entry.variant
		if entry.family=="dwarf":
			actor._rest_behavior.bed_rest.bed=null
			actor._rest_behavior._eyes(false)
			actor._carried_entries.clear()
			actor._reset_part_offsets()
			var active_pose := pose if entry.page!="Settlement" else "Walk" if pose=="Walk" else "Stand"
			match active_pose:
				"Walk": actor._walk_cycle=phase; actor._walk_bob(0)
				"Mine": actor._mining_pose.apply(phase,Vector3(0,1.6,1.4))
				"Fell": actor._felling_pose.apply(phase,Vector3(0,1.2,1.4))
				"Carry":
					entry.cargo.show()
					actor._carry_pose.hold([[entry.cargo,"base:resources:stone:rough_stone"]],sin(phase*TAU)*.02)
				"Sit":
					entry.seat.node.show()
					actor._idle_behavior.seat=entry.seat
					actor._idle_behavior._furniture=self
					actor._idle_behavior._sitting_blend=1
					actor._idle_behavior.elapsed=phase*2
					actor._idle_behavior._pose()
				"Sleep":
					entry.bed.node.show()
					actor._rest_behavior.bed_rest.bed=entry.bed
					actor._rest_behavior.pose="lying"; actor._rest_behavior.blend=1
					actor._rest_behavior.elapsed=phase*4
					actor._rest_behavior._apply_pose()
					actor._rest_behavior._eyes(true)
			var profile: Dictionary=profiles.dwarves[variant]
			# Apply after the rig, so its captured rest scales cannot undo the trial.
			# X=0 for both part pivots; this does not move their vertical anchors.
			actor._body.transform.basis*=Basis.from_scale(Vector3(profile.body_x/actor.proportions.body_width,1,1))
			actor._head.transform.basis*=Basis.from_scale(Vector3(profile.head_x/actor.proportions.head_width,1,1))
			# Preserve original grip/contact transforms during work, carry and rest.
			if active_pose in ["Stand","Walk"]:
				actor._hand_l.position.x-=profile.hand_inset-actor.proportions.relaxed_hand_inset
				actor._hand_r.position.x+=profile.hand_inset-actor.proportions.relaxed_hand_inset
				actor._foot_l.position.x-=profile.foot_inset-actor.proportions.relaxed_foot_inset
				actor._foot_r.position.x+=profile.foot_inset-actor.proportions.relaxed_foot_inset
		else:
			actor.activity="Sleeping" if pose=="Sleep" else "Eating" if pose=="Eat" else "Hunting" if pose=="Run" else "Wandering" if pose=="Walk" else "Idle"
			actor.hop_progress=phase if pose in ["Walk","Run"] else 1.0
			actor.pose_time=phase*5
			var factor: Array=profiles.wolves[variant].visual_scale
			actor.visual.scale=Vector3(factor[0],factor[1],factor[2])
			actor._pose()


func _build_ui() -> void:
	get_window().title="Deepdraft — Dwarf and wolf proportion trials"
	var layer := CanvasLayer.new(); add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left=18; panel.offset_right=-18; panel.offset_top=14
	panel.add_theme_stylebox_override("panel",UITheme.hearth_panel(true)); layer.add_child(panel)
	var column := VBoxContainer.new(); panel.add_child(column)
	var title := Label.new(); title.text="DEEPDRAFT  /  DWARF WIDTH & WOLF PROPORTIONS"
	UITheme.apply_title(title,23); column.add_child(title)
	var row := HBoxContainer.new(); column.add_child(row)
	for page in ["Dwarf A","Dwarf B","Wolves","Settlement"]: _button(page,func(): _select_view(page),row)
	for value in ["Front","Quarter","Side","Colony"]: _button(value,func(): _set_angle(value),row)
	var motions := HBoxContainer.new(); column.add_child(motions)
	for motion in ["Stand","Walk","Mine","Fell","Carry","Sit","Sleep","Run","Eat"]: _button(motion,func(): _set_pose(motion),motions)
	_button("Pause",func(): playing=not playing; _refresh_ui(),motions)
	_button("Settlement trial",func(): choice=(choice+1)%4; _apply_review_pose(); _refresh_ui(),motions)
	caption=Label.new(); column.add_child(caption)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left=18; bottom.offset_right=-18; bottom.offset_top=-103; bottom.offset_bottom=-14
	bottom.add_theme_stylebox_override("panel",UITheme.hearth_panel(true)); layer.add_child(bottom)
	var bottom_column := VBoxContainer.new(); bottom.add_child(bottom_column)
	detail=Label.new(); bottom_column.add_child(detail)
	footer=Label.new(); bottom_column.add_child(footer)
	footer.text="RMB orbit · Wheel zoom · Space pause · Esc exit   |   Approved: Balanced dwarf + Large wolf. Before shows pre-165 shapes."
	footer.add_theme_font_size_override("font_size",13); footer.add_theme_color_override("font_color",UITheme.HEARTH_MUTED)
	for spec in labels:
		var label := Label.new(); label.text=spec.text
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",15 if spec.small else 19)
		label.add_theme_color_override("font_color",Color("E8DBC0"))
		label.add_theme_color_override("font_shadow_color",Color("152120"))
		label.add_theme_constant_override("shadow_offset_x",2); label.add_theme_constant_override("shadow_offset_y",2)
		layer.add_child(label); spec["label"]=label
	reference_panel=PanelContainer.new(); layer.add_child(reference_panel); reference_panel.hide()


func _select_view(value: String) -> void:
	view="Dwarf A" if value=="Lineup" else value
	if not _poses_for_view().has(pose): _set_pose("Stand")
	lineup.visible=view!="Settlement"; settlement.visible=view=="Settlement"; terrain.visible=view=="Settlement"
	for page in pages: pages[page].visible=page==view
	if view=="Settlement": target=Vector3(48,26,47); yaw=-28; pitch=40; zoom=49
	else: target=Vector3(116,22.4,40); yaw=0; pitch=0 if angle in ["Front","Side"] else 18 if angle=="Quarter" else 48; zoom=18.5 if angle!="Colony" else 29
	_update_camera(); _refresh_ui()


func _set_angle(value: String) -> void:
	angle=value
	var turn := 0.0 if angle=="Front" else 28.0 if angle in ["Quarter","Colony"] else 90.0
	for reference in references: reference.node.rotation_degrees.y=reference.facing+turn
	for ruler in rulers: ruler.visible=angle in ["Front","Side"]
	for entry in trials:
		if entry.page=="Settlement": continue
		var degrees := turn
		if entry.family=="wolf": degrees+=90
		entry.node.rotation_degrees.y=degrees
		if entry.has("seat"):
			entry.seat.node.rotation_degrees.y=degrees
			entry.bed.node.rotation_degrees.y=degrees-90
	_select_view(view)


func _set_pose(value: String) -> void:
	pose=value; phase=0; playing=value!="Stand"
	_apply_review_pose(); _refresh_ui()


func _poses_for_view() -> Array:
	if view=="Settlement": return ["Stand","Walk"]
	if view=="Wolves": return ["Stand","Walk","Run","Eat","Sleep"]
	return ["Stand","Walk","Mine","Fell","Carry","Sit","Sleep"]


func _refresh_ui() -> void:
	if caption==null: return
	var angle_label := "Profile" if view=="Wolves" and angle=="Front" else "Head-on" if view=="Wolves" and angle=="Side" else angle
	caption.text="%s · %s · %s · standing dwarf and pine heights fixed" % [view,angle_label,pose]
	if view=="Settlement": caption.text="Settlement · %s · standing dwarf and pine heights fixed" % pose
	buttons.Front.text="Profile" if view=="Wolves" else "Front"
	buttons.Side.text="Head-on" if view=="Wolves" else "Side"
	for name in ["Front","Quarter","Side","Colony"]: buttons[name].disabled=view=="Settlement"
	buttons.Pause.text="Pause" if playing else "Play"
	buttons["Settlement trial"].text="Settlement: "+["Before","Balanced","Lean / Large","Approved"][choice]
	for name in ["Stand","Walk","Mine","Fell","Carry","Sit","Sleep","Run","Eat"]: buttons[name].disabled=not _poses_for_view().has(name)
	buttons["Settlement trial"].disabled=view!="Settlement"
	if view.begins_with("Dwarf"):
		detail.text="Resting hand span: Before 2.60 · Balanced 2.16 · Lean 2.00 blocks. SH reference stays in its authored pose.\nWork, carry and rest use existing grip/contact positions; only idle/walk hands move inward."
	elif view=="Wolves":
		detail.text="Standing H × W × length: Before 1.84 × 0.78 × 1.95 · Balanced 2.12 × 1.05 × 2.83 · Large 2.39 × 1.29 × 3.41\nLarge is approved. Production now uses four-wide, three-high clearance with two-cell flat strides."
	else:
		detail.text="Settlement compares both families together. Approved pairs the Balanced dwarf with the Large wolf.\nPines, other animals, furniture and terrain stay at current sizes. This is a posed visual scene."


func _process(delta: float) -> void:
	if not ready_for_review: return
	if playing and not capture_mode: phase=fposmod(phase+delta*(1.7 if pose=="Run" else .65),1)
	_apply_review_pose()
	for spec in labels:
		spec.label.visible=spec.parent.is_visible_in_tree()
		if spec.label.visible:
			spec.label.size=Vector2(190,50)
			spec.label.position=camera.unproject_position(spec.at)-Vector2(95,15 if spec.small else 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode==KEY_SPACE: playing=not playing; _refresh_ui()
		if event.keycode!=KEY_ESCAPE: return
	super._unhandled_input(event)


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REVIEW_OUT))
	var fingerprint: String=terrain.fingerprint()
	report["profiles"]=profiles
	report["trials"]={}
	_set_pose("Stand")
	for entry in trials:
		if entry.page=="Settlement": continue
		var box := _bounds(entry.node)
		var key: String=entry.page+" / "+str(entry.variant)
		report.trials[key]={"height":box.size.y,"width":box.size.x,"depth":box.size.z,"bottom":box.position.y}
		_check(absf(box.position.y)<.001,"Ground contact: "+key)
		if entry.family=="dwarf":
			var original: Dictionary=report.trials[entry.page+" / 0"]
			_check(absf(box.size.y-original.height)<.001,"Standing dwarf height retained: "+key)
			_check(entry.node.get_node("LogicalBox").shape.size==Vector3(1,3,1),"Dwarf logical clearance retained: "+key)
	for page in ["Dwarf A","Dwarf B","Wolves"]:
		_select_view(page)
		for side in ["Front","Quarter","Side","Colony"]:
			_set_pose("Stand"); _set_angle(side)
			await _capture(page.to_snake_case()+"_"+side.to_lower())
		_set_angle("Quarter")
		var motions := ["Walk","Run","Eat","Sleep"] if page=="Wolves" else ["Walk","Mine","Fell","Carry","Sit","Sleep"]
		for motion in motions:
			buttons[motion].pressed.emit()
			for q in [.2,.55,.93]:
				phase=q; _apply_review_pose()
				_check_contacts(page,motion)
				await _capture(page.to_snake_case()+"_"+motion.to_lower()+"_%02d" % roundi(q*100))
	_set_pose("Stand"); _set_angle("Front")
	for entry in trials:
		if entry.page=="Settlement": continue
		var box := _bounds(entry.node)
		var key: String=entry.page+" / "+str(entry.variant)
		var original: Dictionary=report.trials[key]
		_check(box.size.distance_to(Vector3(original.width,original.height,original.depth))<.001 and absf(box.position.y-original.bottom)<.001,"Pose cycle restores standing dimensions: "+key)
	_set_pose("Stand"); _select_view("Settlement")
	var pine_transforms: Array[Transform3D]=[]
	for spec in specimens:
		if spec.family=="trees": pine_transforms.append(spec.node.transform)
	for i in 4:
		choice=i; _apply_review_pose(); _refresh_ui()
		await _capture("settlement_"+str(i))
	var n := 0
	for spec in specimens:
		if spec.family=="trees":
			_check(spec.node.transform==pine_transforms[n],"Tree unchanged: "+spec.id); n+=1
	_check(terrain.fingerprint()==fingerprint,"Terrain bytes unchanged")
	_check(not SaveManager.is_processing() and SaveManager._save_directory_path=="user://scale_study","Isolated disabled saves")
	report["checks"]=checks; report["failures"]=failures; report["passed"]=failures.is_empty()
	FileAccess.open(REVIEW_OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("PROPORTION_STUDY_OK" if failures.is_empty() else "PROPORTION_STUDY_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_contacts(page: String, motion: String) -> void:
	for entry in trials:
		if entry.page!=page: continue
		var actor: Node3D=entry.node
		_check(is_finite(_bounds(actor).size.length()),"Finite posed bounds")
		if entry.family!="dwarf": continue
		if motion in ["Mine","Fell"]:
			var rig=actor._mining_pose if motion=="Mine" else actor._felling_pose
			var palm: Vector3=actor._hand_r.to_global(rig.PALM)
			_check(palm.distance_to(rig.tool.global_position)<.001,"Main tool grip retained")
			_check(actor._hand_l.to_global(rig.PALM).distance_to(rig.tool.to_global(rig.SUPPORT_GRIP))<.001,"Support tool grip retained")
			if (motion=="Mine" and phase>=.92) or (motion=="Fell" and phase>=.54 and phase<.62):
				var point: Vector3=rig.PICK_POINT if motion=="Mine" else rig.CUTTING_EDGE
				var at := Vector3(0,1.6,1.4) if motion=="Mine" else Vector3(0,1.2,1.4)
				_check(rig.tool.to_global(point).distance_to(actor.to_global(at))<.001,"Work contact retained")
		if motion=="Carry":
			var grips: Array=actor._carry_pose._bundle_grips([[entry.cargo,"base:resources:stone:rough_stone"]])
			_check(actor._hand_l.position.distance_to(grips[0]-actor._hand_l.basis*actor._carry_pose.PALM)<.001,"Carry left grip retained")
			_check(actor._hand_r.position.distance_to(grips[1]-actor._hand_r.basis*actor._carry_pose.PALM)<.001,"Carry right grip retained")


func _capture(id: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(REVIEW_OUT+id+".png")==OK,"Capture "+id)
	report.captures[id]={"view":view,"angle":angle,"pose":pose,"phase":phase,"settlement_trial":choice,"camera_size":camera.size,"camera_transform":str(camera.transform)}
