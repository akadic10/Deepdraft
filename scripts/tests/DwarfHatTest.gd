extends "res://scripts/tests/WorkerCraftingTest.gd"

## Trade hats (doc 304): a dwarf with a trade wears its hat and a Worker goes bare-headed; the
## hair's cut for under a hat takes the full hair's place; nothing is saved. The Miner's candle
## burns while the dwarf is awake in the dark, is out in daylight, by a lit torch in sight and in
## sleep, and its light stays out of rock and under the slice's cut. Portraits show the hat without
## its light. Also: the outline that shows a dwarf behind walls no longer counts rock the slice has
## cut away (the flaw found with the hats).
const WORKER := "base:profession:worker"
const MINER := "base:profession:miner"
const HERE := Vector3(40.5, 21, 39.5)

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Dwarf hat test timed out"); quit(1))
	await _setup_crafting_fixture()
	var assets := root.get_node("DwarfAssets")
	var head: Node3D = worker.get_head()
	worker.position = HERE
	worker.rotation.y = 0.0
	var unsliced: int = worker.get_slice_y()   # the slice is off: every height shows

	# ── Who wears one ──
	_expect(head.get_node_or_null("MeshHat") == null and head.get_node("MeshHair").visible, "a Worker goes bare-headed, with all its hair")
	for key: String in assets.profession_ids():
		var live: bool = assets.profession_enabled(key) and key != WORKER
		_expect((assets.profession_hat(key) != null) == live, "a hat for every trade a dwarf can take, and none for %s otherwise" % key)
	var before: Dictionary = worker.serialize_state()
	worker._complete_profession_change(MINER)   # as the copper pick's pickup leaves it (doc 306, ToolPromotionTest)
	var hat: Node3D = head.get_node_or_null("MeshHat")
	var cut: Node3D = head.get_node_or_null("MeshHairHatted")
	_expect(hat != null and cut != null and not head.get_node("MeshHair").visible, "the Miner's hat is on at once, over the hair's cut for under a hat")
	_expect(_tint_of(cut).is_equal_approx(_tint_of(head.get_node("MeshHair"))), "the hair under the hat keeps the dwarf's hair colour")
	var after: Dictionary = worker.serialize_state()
	after.profession = before.profession
	after.profession_experience = before.profession_experience
	_expect(after.keys() == before.keys() and after.appearance == before.appearance, "a hat adds nothing to the save")
	for key: String in assets.profession_ids():
		if assets.profession_hat(key) == null or key == MINER: continue
		worker._complete_profession_change(key)
		var worn: Node3D = head.get_node_or_null("MeshHat")
		_expect(worn != null and worn.scene_file_path == assets.profession_hat(key).resource_path, "%s wears its own hat" % key)
		_expect(worn.get_node_or_null("HatLight") == null and worn.find_children("*", "Light3D", true, false).is_empty(), "only the Miner's hat has a candle (%s)" % key)
	worker._complete_profession_change(WORKER)
	await _frames(2)
	_expect(head.get_node_or_null("MeshHat") == null and head.get_node_or_null("MeshHairHatted") == null and head.get_node("MeshHair").visible,
		"back to Worker: the hat is gone and the hair is whole")
	_expect(head.find_children("*", "Light3D", true, false).is_empty(), "no light is left behind")

	# A Miner read from a save wears the hat from the start; a bald one has no hair to cut.
	var factory = load("res://scripts/entities/DwarfFactory.gd").new()
	var data: Dictionary = factory.generate(77, {})
	data.profession = MINER
	data.gender = "male"
	data.appearance.gender = "male"
	data.appearance.hair_style = "bald"
	var bald = factory.spawn(data, 77)
	scene.add_child(bald)
	bald.set_process(false)
	_expect(bald.get_head().get_node_or_null("MeshHat") != null and bald.get_head().get_node_or_null("MeshHairHatted") == null, "a bald Miner restored from a save wears the hat, with no hair under it")
	var ghosts := 0
	for mesh: MeshInstance3D in bald.get_head().get_node("MeshHat").find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "OccludedSilhouette":
			ghosts += 1
			_expect(not mesh.get_parent().has_meta(&"hat_flame"), "a candle's flame takes no outline")
	_expect(ghosts == 1, "a hat built with its dwarf has the outline that shows it behind walls")
	bald.free()

	# ── The Miner's candle ──
	worker._complete_profession_change(MINER)
	hat = head.get_node("MeshHat")
	var candle: Node3D = hat.get_node("HatLight")
	candle.set_process(false)
	var light: OmniLight3D = candle.get_node("Candle")
	var flame: MeshInstance3D = hat.find_child("flame", true, false)
	_expect(flame != null and flame.has_meta(&"hat_flame") and not flame.visible and not light.visible, "the candle starts out")
	worker.get_node("Readability").cover(head)
	var outlined := false
	for mesh: Node in hat.find_children("OccludedSilhouette", "MeshInstance3D", true, false): outlined = outlined or mesh.get_parent() != flame
	_expect(outlined and flame.get_node_or_null("OccludedSilhouette") == null, "a hat put on later takes the outline too, its flame does not")
	_set_hour(12.0)
	candle.look()
	_expect(not candle.burning, "in daylight the candle is out")
	_set_hour(0.5)
	candle.look()
	_expect(candle.burning, "in the open at night it burns")
	for i in 12: candle._process(0.05)
	_expect(is_equal_approx(candle.level, 1.0) and flame.visible and light.visible and light.light_energy > 1.0, "its flame and light come up")
	_expect(light.shadow_enabled and light.shadow_caster_mask & 1 == 0, "only rock and built walls shadow it, never the dwarf itself")
	# A lit torch in sight puts it out; a wall between brings it back.
	var torch = _install(TORCH, Vector3i(44, 21, 39), 0)
	var torch_light: OmniLight3D = load("res://scripts/components/FurnitureLighting.gd").light_of(torch.node)
	_expect(torch_light != null and torch_light.is_in_group("furniture_lights"), "a torch's light is one a candle can find")
	candle.look()
	_expect(not candle.burning, "a lit torch in sight puts the candle out")
	var stone: int = blocks.get_id("base:terrain:rock:rock01")
	for y in range(21, 26):
		for z in range(37, 43): world.set_block(42, y, z, stone)
	candle.look()
	_expect(candle.burning, "a torch behind a wall does not")
	torch_light.visible = false
	for y in range(21, 26):
		for z in range(37, 43): world.set_block(42, y, z, blocks.AIR_ID)
	candle.look()
	_expect(candle.burning, "nor does an unlit one")
	# Asleep: lit on the way to bed, out once settled.
	worker._sleeping = true
	worker._rest_behavior.state = "travelling_bed"
	candle.look()
	_expect(candle.burning, "it burns on the way to bed")
	worker._rest_behavior.state = "sleeping"
	candle.look()
	_expect(not candle.burning, "and is out in sleep")
	for i in 12: candle._process(0.05)
	_expect(candle.level == 0.0 and not flame.visible and not light.visible, "the flame and the light go out")
	worker._sleeping = false
	worker._rest_behavior.state = ""

	# The light keeps out of rock and under the slice's cut.
	candle.look()
	for i in 12: candle._process(0.05)
	var seat: Vector3 = light.global_position
	_expect(seat.distance_to(HERE + Vector3(0, 2.6, 0.9)) < 0.01, "in the open the light hangs before the brow")
	world.set_block(40, 23, 40, stone)
	candle._process(0.05)
	_expect(not blocks.is_solid(world.get_live_block(floori(light.global_position.x), floori(light.global_position.y), floori(light.global_position.z))) \
		and light.global_position.z < seat.z, "at a wall's face it draws back out of the rock")
	world.set_block(40, 23, 40, blocks.AIR_ID)
	worker.apply_slice(22)
	candle._process(0.05)
	_expect(worker.visible and light.global_position.y <= 22.86, "under a slice that cuts through the dwarf, the light stays below the cut")
	worker.apply_slice(unsliced)

	# Underground by day: a sealed chamber is dark at noon.
	var lighting = load("res://scripts/components/UndergroundLighting.gd").new()
	scene.add_child(lighting)
	_set_hour(12.0)
	candle.look()
	_expect(not candle.burning, "at noon in the open it is out again")
	for x in range(38, 44):
		for z in range(37, 43):
			world.set_block(x, 24, z, stone)
			if x in [38, 43] or z in [37, 42]:
				for y in range(21, 24): world.set_block(x, y, z, stone)
	for i in 600:
		await process_frame
		if not lighting.is_updating(): break
	_expect(not lighting.is_updating() and lighting.actor_sky_at(HERE + Vector3.UP * 1.5) < 0.05, "a sealed chamber gets no daylight")
	candle.look()
	_expect(candle.burning, "underground the candle burns at noon")

	# The outline that shows a dwarf behind walls: rock the slice has cut away is no cover.
	var outline = worker.get_node("Readability")
	outline.set_process(false)
	worker.apply_slice(unsliced)
	outline.refresh()
	_expect(outline.material.get_shader_parameter("cover_count") > 0, "the chamber's walls and roof cover the dwarf")
	for x in range(38, 44):
		for z in range(37, 43):
			if x in [38, 43] or z in [37, 42]:
				for y in range(21, 24): world.set_block(x, y, z, blocks.AIR_ID)
	outline.refresh()
	_expect(outline.material.get_shader_parameter("cover_count") > 0, "a roof alone still covers it")
	worker.apply_slice(23)
	outline.refresh()
	_expect(outline.material.get_shader_parameter("cover_count") == 0, "a roof the slice has cut away covers nothing")
	worker.apply_slice(unsliced)

	# ── Portraits and rest ──
	candle.look()
	for i in 12: candle._process(0.05)
	var texture := TextureRect.new()
	scene.add_child(texture)
	var portrait = load("res://scripts/ui/DwarfPortrait.gd")
	var model: Node3D = portrait.create_model(portrait.create_viewport(texture), worker)
	var pictured := model.find_child("MeshHat", true, false)
	var pictured_flame := model.find_child("flame", true, false) as MeshInstance3D
	_expect(pictured != null and model.find_children("*", "Light3D", true, false).is_empty(), "a portrait shows the hat without its light")
	_expect(pictured_flame != null and not pictured_flame.visible and flame.visible, "and with the candle unlit, while the dwarf's own burns")
	texture.free()
	var rest = worker._rest_behavior
	rest._lying_head_rest = -1.0
	var hatted: float = rest._lying_head_height()
	worker._complete_profession_change(WORKER)
	rest._lying_head_rest = -1.0
	_expect(is_equal_approx(hatted, rest._lying_head_height()), "a hat does not lift a lying head")

	for failure: String in failures: push_error(failure)
	print("DWARF_HAT_OK: hats by trade, hair under hats, nothing saved, the candle's rule and light, portraits, rest, sliced cover" if failures.is_empty() else "DWARF_HAT_FAIL")
	quit(0 if failures.is_empty() else 1)


func _install(key: String, origin: Vector3i, yaw := 0):
	furniture._install(key, furniture.get_defs()[key], origin, yaw)
	return furniture._installed[furniture._next_installed_id - 1]


func _set_hour(hour: float) -> void:
	clock_node.season = "summer"
	clock_node.day = 1
	clock_node.hour = hour


## The colour a part was tinted with, whether or not the world's lighting has taken its material.
func _tint_of(part: Node) -> Color:
	for mesh: MeshInstance3D in preload("res://scripts/components/VoxelShadowSetup.gd").visual_meshes(part):
		if mesh.name == "OccludedSilhouette": continue
		var material := mesh.material_override
		if material is StandardMaterial3D: return (material as StandardMaterial3D).albedo_color
		if material is ShaderMaterial: return (material as ShaderMaterial).get_shader_parameter("tint")
	return Color.BLACK
