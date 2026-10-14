extends "res://tools/animal_pilot/AnimalPilot.gd"

var species := "deer"
const DEST := "res://tmp/wildlife_faceted_20261013/captures/"

func _ui() -> void:
	super._ui()
	for label in find_children("*","Label",true,false):
		if label.text=="DEEPDRAFT  /  DEER ART REVIEW": label.text="DEEPDRAFT / COMPLETE WILDLIFE FAMILY"

func _build_actors() -> void:
	wildlife=load("res://scripts/systems/WildlifeManager.gd").new()
	add_child(wildlife); wildlife.set_process(false)
	var factory := DwarfFactory.new()
	reference=factory.spawn(factory.generate(141,{}),951)
	add_child(reference); reference.position=Vector3(40,21,41)
	reference.set_process(false); reference.get_node("Readability").set_process(false); reference.hide()
	_species("deer")

func _species(value: String) -> void:
	for actor in actors: actor.free()
	actors.clear(); wildlife.animals.clear()
	species=value
	var table: String={"rabbit":"_models","deer":"_deer_models","wolf":"_wolf_models","duck":"_duck_models"}[species]
	var current: Dictionary=wildlife.get(table)
	for i in 2:
		var models := current.duplicate()
		wildlife.set(table,models)
		var actor: Node3D=wildlife.call("add_"+species,species+":art:"+str(i),Vector3i(37+i*5,21,40),155)
		actors.append(actor)
	wildlife.set(table,current)

func _set_view(value: String) -> void:
	view=value
	var yaw := 145.0
	var elevation := 22.0
	match value:
		"Front": yaw=180
		"Side": yaw=90
		"Rear": yaw=35
		"Colony": elevation=52
	for i in actors.size(): actors[i].rotation_degrees.y=yaw+180*i
	reference.visible=value=="Dwarf scale"
	camera.size=18.0 if value=="Colony" else 9.0
	var target := Vector3(40,22.4 if species=="deer" else 21.8,40.5)
	camera.position=target+Vector3(0,sin(deg_to_rad(elevation)),cos(deg_to_rad(elevation)))*26
	camera.look_at(target)
	_labels()

func _apply() -> void:
	for actor in actors:
		actor.activity={"Stand":"Idle","Walk":"Wandering","Flee":"Fleeing","Graze":"Eating" if species=="wolf" else "Grazing","Rest":"Sleeping"}[mode]
		actor.hop_progress=phase if mode in ["Walk","Flee"] else 1.0
		actor.pose_time=phase*5
		actor._pose()
	_labels()

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(DEST)
	for value in ["rabbit","deer","wolf","duck"]:
		_species(value)
		labels[0].text="VIEW A / "+species; labels[1].text="OPPOSITE / "+species
		for angle in ["Three-quarter","Side","Rear","Colony","Dwarf scale"]:
			_set_mode("Stand"); _set_view(angle)
			await _capture(species+"_"+angle.to_snake_case())
		for action in ["Walk","Graze","Rest"]:
			_set_mode(action); _set_view("Side")
			phase=.25; _apply()
			await _capture(species+"_"+action.to_lower())
		if species=="duck":
			for sex in ["male","female"]:
				for state in ["land","water","air"]:
					for actor in actors:
						actor.sex=sex; actor.mode=state; actor.launch_left=0
						actor.flight=PackedVector3Array([Vector3.ZERO,Vector3.ONE,Vector3.ONE*2,Vector3.ONE*3,Vector3.ONE*4])
						actor.flight_index=2; actor.pose_time=.10
						actor.activity="Flying" if state=="air" else "Idle"
						actor._pose()
						actor.position.y=22.2 if state=="air" else 21
					_set_view("Three-quarter")
					await _capture("duck_"+sex+"_"+state)
	print("WILDLIFE_FACETED_CAPTURE_OK: 38 native production views")
	get_tree().quit()

func _capture(id: String) -> void:
	caption.text=species.capitalize()+" / "+id.replace("_"," ")+" / production poses on a dry review stage"
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(DEST+id+".png")==OK)
