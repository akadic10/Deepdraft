extends SceneTree

## Installed art and runtime material selection must reproduce the accepted study.
const Shadows = preload("res://scripts/components/VoxelShadowSetup.gd")
const STUDY := "res://assets/models/studies/hand_hewn_timber/"
var checks := 0
var failures: Array[String]=[]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for id in ["SaveManager","WorldClock","TaskManager","RoomManager","StockpileManager"]:
		root.get_node(id).set_process(false)
	var controller=load("res://scripts/systems/FurniturePlacementController.gd").new()
	controller._load_defs()
	var materials := root.get_node("CraftMaterials")
	var mapping := {"log_table":"dining_table","log_chair":"log_stool","board_game_table":"game_table","crude_workbench":"workbench"}
	for id: String in mapping:
		var key := "base:furniture:"+id
		var definition: Dictionary=controller.get_defs()[key]
		_expect(definition.material_palette=="hand_hewn_timber",id+" dedicated palette")
		for wood in ["oak","pine","juniper","applewood"]:
			var actual: Node3D=controller._instance_model(key,controller._make_solid_material())
			materials.apply_palette(actual,definition,"base:material:"+wood)
			var expected: Node3D=load(STUDY+mapping[id]+"_"+wood+".glb").instantiate()
			_compare(actual,expected,id+" "+wood)
			actual.free(); expected.free()
	var items=load("res://scripts/systems/ItemDropManager.gd").new()
	root.add_child(items); items.set_process(false)
	for wood in ["oak","pine","juniper","applewood"]:
		var item_id: String="apple_wood" if wood=="applewood" else wood+"_log"
		var actual: Node3D=items.create_item_visual("base:resources:wood:"+item_id)
		var expected: Node3D=load(STUDY+"timber_"+wood+".glb").instantiate()
		_compare(actual,expected,item_id)
		actual.free(); expected.free()
	controller.free(); items.free()
	for failure in failures: push_error(failure)
	print("HAND_HEWN_PRODUCTION_PASS " if failures.is_empty() else "HAND_HEWN_PRODUCTION_FAIL ",checks," checks")
	quit(0 if failures.is_empty() else 1)

func _compare(actual: Node3D,expected: Node3D,label: String) -> void:
	var observed := Shadows.visual_meshes(actual)
	var reference := Shadows.visual_meshes(expected)
	_expect(observed.size()==1 and reference.size()==1,label+" one visual surface")
	if observed.size()!=1 or reference.size()!=1: return
	var a := observed[0].mesh.surface_get_arrays(0)
	var b := reference[0].mesh.surface_get_arrays(0)
	_expect(a[Mesh.ARRAY_VERTEX]==b[Mesh.ARRAY_VERTEX] and a[Mesh.ARRAY_INDEX]==b[Mesh.ARRAY_INDEX],label+" accepted geometry")
	var matches: bool=a[Mesh.ARRAY_COLOR].size()==b[Mesh.ARRAY_COLOR].size()
	if matches:
		for i in a[Mesh.ARRAY_COLOR].size():
			var delta: Color=a[Mesh.ARRAY_COLOR][i]-b[Mesh.ARRAY_COLOR][i]
			if maxf(absf(delta.r),maxf(absf(delta.g),absf(delta.b)))>1.0/255+.0001: matches=false
	_expect(matches,label+" every imported palette color matches approved variant")
	var proxy := Shadows.proxy_for_visual(observed[0])
	_expect(proxy!=null,label+" proxy retained")
	_expect(observed[0].cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,label+" visual casting off")
	_expect(proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,label+" shadow-only proxy")

func _expect(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
