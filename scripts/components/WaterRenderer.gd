extends Node3D

## Opaque, fractionally filled voxel water. One mesh per 32×32 tile; no nodes
## per cell. Geometry builds from private snapshots on workers; only bounded
## snapshot/mesh uploads run here. The terrain mesh renders the bed underneath.
var terrain: Node3D
var material: ShaderMaterial
var _tiles: Dictionary = {}
var _revision := -1
var _slice := -1
var motion := preload("res://scripts/components/WaterSurfaceMotion.gd").new()
var _motion_time := -1.0
var _motion_flow: RefCounted
var _falls: Dictionary = {}
var _splash_sites: Dictionary = {}
var _splash: MultiMeshInstance3D
var _sound: Node3D
const MeshBuilder := preload("res://scripts/components/WaterMeshBuilder.gd")
const Flow := preload("res://scripts/components/WaterFlow.gd")
var _pending: Dictionary = {} # Tile -> first dirty wall-clock time; repeated edits coalesce.
var _jobs: Array[Dictionary] = []
var _last_inputs: Dictionary = {}
var _epoch := 0
var _view_dirty := true
var _dispatch_count := 0
var _built := 0
var _unchanged := 0
var _stale := 0
var last_mesh_work_usec := 0
var last_snapshot_usec := 0
var last_upload_usec := 0
var last_worker_usec := 0
var profile_updates := false
var last_update_ms: Dictionary = {}

func _ready() -> void:
	terrain.visible_volume_changed.connect(func(): _view_dirty = true)
	WaterManager.surface_changed.connect(_on_surface_changed)
	var base := StandardMaterial3D.new()
	base.vertex_color_use_as_albedo = true
	base.roughness = 0.65
	base.metallic_specular = 0.12
	material = terrain.underground_lighting.make_material(base,true)
	material.set_shader_parameter("water_surface",true)
	material.set_shader_parameter("water_motion",motion.upload())
	_splash = MultiMeshInstance3D.new()
	_splash.multimesh = MultiMesh.new()
	_splash.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_splash.multimesh.mesh = BoxMesh.new()
	_splash.multimesh.instance_count = 512
	_splash.multimesh.visible_instance_count = 0
	var foam := StandardMaterial3D.new()
	foam.albedo_color = Color("#C6EDF0")
	_splash.material_override = terrain.underground_lighting.make_material(foam)
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)
	var stones := preload("res://scripts/components/WaterStones.gd").new()
	stones.name = "Stones"
	stones.terrain = terrain
	add_child(stones)

func is_loading_complete() -> bool:
	return WaterManager.initialized and not _view_dirty and _pending.is_empty() and _jobs.is_empty() and _revision==WaterManager.revision and _slice==terrain.slice_y

func _process(_delta: float) -> void:
	if profile_updates: last_update_ms.clear()
	var started := Time.get_ticks_usec() if profile_updates else 0
	visible = WaterManager.initialized
	if not WaterManager.initialized: return
	if _sound == null:
		_sound = preload("res://scripts/components/WaterSound.gd").new()
		_sound.water_view = self
		add_child(_sound)
	if _motion_flow != WaterManager.flow or WaterManager.elapsed < _motion_time or _revision != WaterManager.revision:
		_motion_flow = WaterManager.flow
		_motion_flow.track_surface_motion = true
		_motion_flow.surface_flux.clear()
		_motion_time = WaterManager.elapsed
		motion.reset()
	material.set_shader_parameter("water_time",WaterManager.elapsed)
	var stage := Time.get_ticks_usec() if profile_updates else 0
	var motion_started := Time.get_ticks_usec()
	var motion_budget := maxi(1,roundi(float(WorldGenerator.water_profile.rendering.get("motion_budget_ms",1.0))*1000.0))
	var motion_delta: float = WaterManager.elapsed-_motion_time
	if motion_delta >= 0.2 and not motion.is_updating():
		motion.gain = float(WorldGenerator.water_profile.rendering.surface_speed)*2.0
		motion.begin_update(WaterManager.flow,motion_delta)
		_motion_time = WaterManager.elapsed
	# Snapshot capture counts against the same soft budget. Current samples may
	# finish while paused, then remain frozen until simulation time advances.
	motion.advance(maxi(1,motion_budget-(Time.get_ticks_usec()-motion_started)))
	if profile_updates: last_update_ms.motion = (Time.get_ticks_usec()-stage)/1000.0
	stage = Time.get_ticks_usec() if profile_updates else 0
	if _revision != WaterManager.revision or _slice != terrain.slice_y or _view_dirty:
		_invalidate_view()
	if profile_updates: last_update_ms.view = (Time.get_ticks_usec()-stage)/1000.0
	_drain_mesh_work()
	if profile_updates: last_update_ms.mesh = last_mesh_work_usec/1000.0
	stage = Time.get_ticks_usec() if profile_updates else 0
	material.set_shader_parameter("water_motion",motion.upload())
	if profile_updates: last_update_ms.texture = (Time.get_ticks_usec()-stage)/1000.0
	stage = Time.get_ticks_usec() if profile_updates else 0
	_animate_splash()
	if profile_updates:
		last_update_ms.splash = (Time.get_ticks_usec()-stage)/1000.0
		last_update_ms.total = (Time.get_ticks_usec()-started)/1000.0

func _animate_splash() -> void:
	var index := 0
	var camera := get_viewport().get_camera_3d()
	for sites: Array in _splash_sites.values():
		for site: Dictionary in sites:
			var origin: Vector3 = site.point
			var strength := clampf(motion.velocity(site.key).length()/0.3,0.0,1.0)
			if strength < 0.1 or (camera != null and camera.global_position.distance_squared_to(origin)>6400): continue
			var seed_value := fposmod(origin.x*0.754877+origin.z*0.56984,1.0)
			for j in 3:
				if index >= 512: break
				var phase := fposmod(WaterManager.elapsed*(0.7+seed_value*0.3)+j*0.371+seed_value,1.0)
				var height := sin(phase*PI)*(0.2+strength*0.3)
				var angle := seed_value*TAU+j*2.39996
				var direction := Vector3(cos(angle),0,sin(angle))
				var pos := origin+direction*phase*0.38+Vector3(0,height,0)
				var size := (0.07+0.035*seed_value)*sin(phase*PI)*strength
				_splash.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),pos))
				index += 1
	_splash.multimesh.visible_instance_count = index

func _invalidate_view() -> void:
	_epoch += 1
	_view_dirty = false
	_revision = WaterManager.revision
	_slice = terrain.slice_y
	_last_inputs.clear()
	# An old slice must never linger while workers finish (including cave discovery).
	# Normal level changes retain the old mesh until its replacement is complete.
	for tile: Vector2i in _tiles:
		_tiles[tile].visible = false
		_queue_tile(tile)
	_falls.clear()
	_splash_sites.clear()
	for key: Vector3i in WaterManager.flow.mass:
		_queue_tile(Vector2i(int(key.x/32.0),int(key.z/32.0)))

## A tile keeps its last build until its water moved visibly: by
## rendering.redraw_level_step since that build, or across standing depth. In a
## steady river 73% of tile changes per tick are under 1/1024 block (2026-10-22
## probe); redrawing each one kept the mesh queue seconds behind. A changed cell
## also counts for the neighbouring tile whose border halo holds it.
func _on_surface_changed(cells: Array) -> void:
	var flow = WaterManager.flow
	var standing := roundi(WaterManager.standing_depth*Flow.UNITS)
	var step := roundi(float(WorldGenerator.water_profile.rendering.redraw_level_step)*Flow.UNITS)
	for cell: Vector3i in cells:
		var units := int(flow.mass.get(cell,0))
		var checked: Array[Vector2i] = []
		for offset: Vector2i in [Vector2i.ZERO,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var col := Vector2i(cell.x,cell.z)+offset
			var tile := Vector2i(int(col.x/32.0),int(col.y/32.0))
			if tile in checked or _pending.has(tile): continue
			checked.append(tile)
			if not _last_inputs.has(tile):
				_queue_tile(tile)
				continue
			var built: Dictionary = _last_inputs[tile]
			# A tile drawn empty keeps no mass; only newly standing water matters.
			var before := int(built.mass.get(cell,0))
			if (before>=standing) != (units>=standing) or (not built.visible.is_empty() and absi(units-before)>=step):
				_queue_tile(tile)

func _queue_tile(tile: Vector2i) -> void:
	if tile.x < 0 or tile.y < 0 or tile.x >= 32 or tile.y >= 32: return
	if not _pending.has(tile): _pending[tile] = Time.get_ticks_usec()

func _drain_mesh_work() -> void:
	var started := Time.get_ticks_usec()
	var settings: Dictionary = WorldGenerator.water_profile.rendering
	var budget_usec := maxi(1,roundi(float(settings.mesh_budget_ms)*1000.0))
	last_snapshot_usec = 0
	last_upload_usec = 0
	for tile: Vector2i in WaterManager.dirty_tiles: _queue_tile(tile)
	WaterManager.dirty_tiles.clear()
	# Poll first. Never wait for an unfinished task during a frame.
	for i in range(_jobs.size()-1,-1,-1):
		var job := _jobs[i]
		if not WorkerThreadPool.is_task_completed(job.task): continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.remove_at(i)
		if job.epoch == _epoch:
			var upload_started := Time.get_ticks_usec()
			_assign_mesh(job.tile,job.builder.result)
			last_upload_usec += Time.get_ticks_usec()-upload_started
			last_worker_usec = job.builder.result.build_usec
			_last_inputs[job.tile] = job.builder.snapshot
			_built += 1
		else:
			_stale += 1
		# Changes made during a build are still in _pending, so they cannot be lost.
		if Time.get_ticks_usec()-started >= budget_usec: break
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	while _jobs.size() < int(settings.mesh_jobs) and Time.get_ticks_usec()-started < budget_usec:
		var tile := _next_tile(camera)
		if tile.x < 0: break
		var queued_usec: int = _pending[tile]
		_pending.erase(tile)
		var capture_started := Time.get_ticks_usec()
		var snapshot := _capture(tile)
		last_snapshot_usec += Time.get_ticks_usec()-capture_started
		# Compare exact render inputs. Never quantize away small shore/step faces.
		if _last_inputs.has(tile) and snapshot == _last_inputs[tile]:
			_unchanged += 1
			continue
		var builder := MeshBuilder.new()
		builder.snapshot = snapshot
		var task := WorkerThreadPool.add_task(builder.build,false,"water_tile")
		_jobs.append({"task":task,"builder":builder,"tile":tile,"epoch":_epoch,"queued_usec":queued_usec})
	last_mesh_work_usec = Time.get_ticks_usec()-started

func _next_tile(camera: Camera3D) -> Vector2i:
	var oldest_turn := _dispatch_count % 8 == 7 or camera == null
	var best := Vector2i(-1,-1)
	var best_score := INF
	for tile: Vector2i in _pending:
		var busy := false
		for job: Dictionary in _jobs:
			if job.tile == tile: busy = true; break
		if busy: continue
		var score := float(_pending[tile])
		if not oldest_turn:
			var x := tile.x*32+16
			var z := tile.y*32+16
			var center := Vector3(x,mini(terrain.slice_y,WorldGenerator.get_surface_y(x,z))+1,z)
			score = camera.global_position.distance_squared_to(center)
			if not camera.is_position_in_frustum(center): score += 1048576.0
		if score < best_score: best = tile; best_score = score
	if best.x >= 0: _dispatch_count += 1
	return best

func _capture(tile: Vector2i) -> Dictionary:
	var flow = WaterManager.flow
	var snapshot := {"tile":tile,"slice":terrain.slice_y,"standing_depth":WaterManager.standing_depth,
		"epsilon":flow.epsilon,"palette":WorldGenerator.water_profile.rendering.duplicate(true),
		"spans":{},"mass":{},"visible":{}}
	# Copy one compact tile plus its halo in a single pass. Every mutable container
	# is private; side faces/free-outlet checks can read neighboring columns safely.
	for x in range(tile.x*32-1,tile.x*32+33):
		for z in range(tile.y*32-1,tile.y*32+33):
			var col := Vector2i(x,z)
			var spans: Array = flow.spans(col)
			snapshot.spans[col] = spans.duplicate()
			for span: Vector2i in spans:
				var key := Vector3i(x,span.x,z)
				var units: int = flow.mass.get(key,0)
				if units <= 0: continue
				snapshot.mass[key] = units
				if x < tile.x*32 or x >= tile.x*32+32 or z < tile.y*32 or z >= tile.y*32+32: continue
				var amount := float(units)/Flow.UNITS
				if amount < WaterManager.standing_depth or key.y > terrain.slice_y: continue
				var top := minf(key.y+amount,terrain.slice_y+1.0)
				if key.y <= WorldGenerator.get_surface_y(x,z) and not terrain.is_revealed_air(Vector3i(x,mini(ceili(top)-1,terrain.slice_y),z)): continue
				snapshot.visible[key] = motion.slot(key)
	# Changes to invisible pools/films must not keep rebuilding an empty mesh.
	if snapshot.visible.is_empty():
		snapshot.spans.clear()
		snapshot.mass.clear()
	return snapshot

func _assign_mesh(tile: Vector2i, result: Dictionary) -> void:
	_falls[tile] = result.falls
	_splash_sites[tile] = result.splash_sites
	if not _tiles.has(tile):
		var node := MeshInstance3D.new()
		node.name = "Water_%d_%d" % [tile.x,tile.y]
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_tiles[tile] = node
	_tiles[tile].visible = true
	if result.arrays[Mesh.ARRAY_VERTEX].is_empty():
		_tiles[tile].mesh = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,result.arrays)
	_tiles[tile].mesh = mesh

## Synchronous entry for geometry fixtures only; live frames always use the queue.
func _build(tile: Vector2i) -> void:
	var builder := MeshBuilder.new()
	builder.snapshot = _capture(tile)
	builder.build()
	_assign_mesh(tile,builder.result)

func get_mesh_stats() -> Dictionary:
	var oldest := Time.get_ticks_usec()
	for stamp: int in _pending.values(): oldest = mini(oldest,stamp)
	for job: Dictionary in _jobs: oldest = mini(oldest,job.queued_usec)
	return {"pending":_pending.size(),"in_flight":_jobs.size(),"built":_built,
		"unchanged":_unchanged,"stale":_stale,"oldest_ms":(Time.get_ticks_usec()-oldest)/1000.0,
		"main_ms":last_mesh_work_usec/1000.0,"snapshot_ms":last_snapshot_usec/1000.0,
		"upload_ms":last_upload_usec/1000.0,"worker_ms":last_worker_usec/1000.0}

func _exit_tree() -> void:
	# Jobs only own copied data, but must be joined before releasing their owners.
	for job: Dictionary in _jobs: WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()
