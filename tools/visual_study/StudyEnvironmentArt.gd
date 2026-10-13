extends Node3D

## Deterministic native geometry for the environment art sample. These are
## display-only prototypes: no item definitions, colliders or simulation IDs.
const MeshBuilder = preload("StudyMesh.gd")
const ORIGIN := Vector3(32,0,32)
var entries: Array[Dictionary] = []
var terrain
var material: Material
var triangle_count := 0

func build(terrain_owner: Node, surface_material: Material) -> void:
	terrain = terrain_owner
	material = surface_material
	for spec in [[Vector2i(2,23),true,701],[Vector2i(8,29),false,702],
		[Vector2i(18,29),true,703],[Vector2i(30,26),true,704],
		[Vector2i(30,5),false,705],[Vector2i(3,29),true,706]]:
		var cell: Vector2i = spec[0]
		var floor_y: float = terrain.surface_height(cell.x,cell.y)+1
		_tree(Vector3(cell.x+.5,floor_y,cell.y+.5),spec[1],spec[2])
	_ground()
	_room_details()

func _publish(builder: RefCounted, floor_y: float) -> void:
	if builder.vertices.is_empty(): return
	var node := MeshInstance3D.new()
	node.mesh = builder.to_mesh()
	node.material_override = material
	node.position = ORIGIN
	add_child(node)
	entries.append({"node":node,"floor":floor_y})
	triangle_count += builder.indices.size()/3

func set_slice(level: int) -> void:
	for entry in entries: entry.node.visible = entry.floor <= level+1

func _tree(base: Vector3, fir: bool, tree_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var mesh = MeshBuilder.new()
	var bark := Color("51412d").srgb_to_linear()
	var height := 8.6 if fir else 6.4
	mesh.log_between(base,base+Vector3(.12,height-.5,-.1),.36,bark)
	for i in range(5):
		var angle := i*TAU/5.0
		mesh.log_between(base+Vector3(0,.5,0),base+Vector3(cos(angle)*.85,.09,sin(angle)*.85),.19,bark)
	var palette := [Color("314b35"),Color("405c37"),Color("52683b"),Color("5e7542"),Color("75854a")]
	if fir:
		for tier in range(6):
			var y := 2.0+tier*1.05
			var radius := 2.4-tier*.34
			var count := 7 if tier < 4 else 5
			for limb in range(count):
				var angle := limb*TAU/count+tier*.7+rng.randf_range(-.15,.15)
				var outward := Vector3(cos(angle),0,sin(angle))
				var tip := base+outward*radius+Vector3(0,y-.1,0)
				mesh.log_between(base+Vector3(0,y+.55,0),tip,.105,bark)
				for clump in range(3):
					var distance_from_trunk := radius*(.28+.30*clump)
					var centre := base+outward*distance_from_trunk+Vector3(rng.randf_range(-.18,.18),y+.3-clump*.11,rng.randf_range(-.18,.18))
					var width := (.95 if tier<4 else .7)*rng.randf_range(.85,1.15)
					var color: Color = palette[rng.randi_range(0,3)].srgb_to_linear()
					mesh.box(centre,Vector3(width,.75,width*1.18),color,.12,angle)
			mesh.box(base+Vector3(0,y+.65,0),Vector3(radius*.7,.9,radius*.7),palette[2].srgb_to_linear(),.13,tier*.35)
		mesh.box(base+Vector3(.05,8.4,0),Vector3(.45,.85,.5),palette[3].srgb_to_linear(),.1,.3)
	else:
		for limb in range(8):
			var angle := limb*TAU/8.0+.3
			var radius := rng.randf_range(1.5,2.35)
			var centre := base+Vector3(cos(angle)*radius,4.2+rng.randf_range(-.5,1.1),sin(angle)*radius)
			mesh.log_between(base+Vector3(0,2.1,0),centre,.22,bark)
			for clump in range(7):
				var position := centre+Vector3(rng.randf_range(-.8,.8),rng.randf_range(-.35,.75),rng.randf_range(-.8,.8))
				var size := rng.randf_range(.9,1.55)
				mesh.box(position,Vector3(size,size*.8,size),palette[rng.randi_range(1,4)].srgb_to_linear(),.18,rng.randf_range(-.5,.5))
		mesh.box(base+Vector3(.1,5.5,.1),Vector3(2.4,1.5,2.2),palette[3].srgb_to_linear(),.22,.3)
	_publish(mesh,base.y)

func _ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77109
	var layers: Dictionary = {}
	for z in range(16,32):
		for x in range(32):
			var bounds: Vector2i = terrain.river_bounds(z)
			if x >= bounds.x and x <= bounds.y: continue
			var y: float = terrain.surface_height(x,z)+1
			if not layers.has(y): layers[y] = MeshBuilder.new()
			var mesh = layers[y]
			var left_path := 7.5+(z-16)*.34
			var right_path := 17.5+(z-16)*.16
			var path := absf(x+.5-left_path) < 1.3 or absf(x+.5-right_path)<1.0
			var bank: bool = absi(x-bounds.x)<3 or absi(x-bounds.y)<3
			if path:
				var stone := Color("777565").lerp(Color("9d9072"),rng.randf()).srgb_to_linear()
				mesh.box(Vector3(x+.5,y+.025,z+.5),Vector3(.95,.085,.93),stone,.03,rng.randf_range(-.035,.035))
			elif rng.randf()<.35 or bank:
				# Small stepped leaf clumps, backed by a muted soil patch.
				var base := Vector3(x+rng.randf(),y,z+rng.randf())
				mesh.box(base+Vector3(0,.012,0),Vector3(.7,.035,.6),Color("38452c").srgb_to_linear(),.01)
				for blade in range(4):
					var h := rng.randf_range(.14,.42)
					var p := base+Vector3(rng.randf_range(-.27,.27),h*.5,rng.randf_range(-.25,.25))
					mesh.box(p,Vector3(.12,h,.15),Color("536a36").lerp(Color("80904a"),rng.randf()).srgb_to_linear(),.03,rng.randf()*TAU)
			if (bank or x<3) and rng.randf()<.27:
				var size := rng.randf_range(.4,1.0)
				var base := Vector3(x+.5,y+size*.22,z+.5)
				mesh.box(base,Vector3(size,size*.55,size*.85),Color("647075").lerp(Color("858778"),rng.randf()).srgb_to_linear(),size*.15,rng.randf()*TAU)
	# Waterline rocks, a few above the surface with mossy shoulders.
	for z in [4,8,14,16,20,25,29]:
		var bounds: Vector2i = terrain.river_bounds(z)
		var y := 21.75 if z<13 else 16.75
		if not layers.has(y): layers[y] = MeshBuilder.new()
		var mesh = layers[y]
		for x in [bounds.x+.25,bounds.y+.6]:
			mesh.box(Vector3(x,y+.1,z+.3),Vector3(.75,.55,1.05),Color("566665").srgb_to_linear(),.13,.4)
			mesh.box(Vector3(x+.1,y+.38,z+.35),Vector3(.45,.08,.65),Color("4d5f35").srgb_to_linear(),.02,.4)
	for layer: float in layers: _publish(layers[layer],layer)

func _room_details() -> void:
	var mesh = MeshBuilder.new()
	var wood := Color("705031").srgb_to_linear()
	var timber := Color("936a3e").srgb_to_linear()
	var metal := Color("343c3c").srgb_to_linear()
	# Thick timber wall shelf and stacked supply crates in the dining room.
	for x in [3.5,10.25]:
		mesh.box(Vector3(x,22.0,5.0),Vector3(.22,2.0,.3),wood,.04)
	mesh.box(Vector3(6.85,22.0,4.9),Vector3(7.0,.22,.65),timber,.04)
	for x in [4.2,5.3,8.1,9.3]:
		mesh.box(Vector3(x,22.4,4.85),Vector3(.65,.48,.5),Color("a88d5f").srgb_to_linear(),.07,.08)
	for pos in [Vector3(4,21,11),Vector3(4,22,11),Vector3(5.1,21,11)]:
		mesh.box(pos+Vector3(0,.45,0),Vector3(.95,.9,.85),wood,.06)
		for offset in [-.28,.28]:
			mesh.box(pos+Vector3(offset,.45,.44),Vector3(.11,.93,.06),timber,.02)
		mesh.box(pos+Vector3(0,.1,.44),Vector3(.95,.12,.06),timber,.02)
		mesh.box(pos+Vector3(0,.81,.44),Vector3(.95,.12,.06),timber,.02)
	# Low workshop supply shelf: recognizable physical contents at RTS distance.
	mesh.box(Vector3(20,21.8,6),Vector3(1.0,1.6,2.7),wood,.04)
	for z in [5.1,6.0,6.9]:
		mesh.box(Vector3(20,22.7,z),Vector3(.65,.3,.5),metal,.05,.1)
	_publish(mesh,21.0)
