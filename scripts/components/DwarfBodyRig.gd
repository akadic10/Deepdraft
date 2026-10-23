extends RefCounted

## A dwarf's body (doc 41 / 41b): part assembly, runtime tinting, the work and
## carry rigs, and the procedural idle bob. DwarfAgent keeps its part fields
## for the other components; they point at the same nodes built here.
##
## VISUAL CONTRACT (doc 41, hard rules):
##   - Four-part silhouette: oversized head, compact torso, DETACHED floating
##     hands and feet. No arms, no legs — ever.
##   - Parts are independent MeshInstance3D-bearing nodes; NEVER merged into a
##     single mesh (equipment attaches as children; animation drives transforms).
##   - GLBs share authored rig coordinates. Registry-owned proportions narrow
##     the torso/head and relaxed stance; palms and vertical anchors stay fixed.

const FellingPose = preload("res://scripts/components/DwarfFellingPose.gd")
const MiningPose = preload("res://scripts/components/DwarfMiningPose.gd")
const ConstructionPose = preload("res://scripts/components/DwarfConstructionPose.gd")
const CarryPose = preload("res://scripts/components/DwarfCarryPose.gd")
const ShadowSetup = preload("res://scripts/components/VoxelShadowSetup.gd")

var agent: DwarfAgent
var head: Node3D
var body: Node3D
var hand_l: Node3D
var hand_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var felling_pose: RefCounted
var mining_pose: RefCounted
var construction_pose: RefCounted
var carry_pose: RefCounted
## What the hands hold: [[node: Node3D, item_key: String], ...]. The work
## executor owns the pickup/set-down rules; the body only presents the cargo.
var carried_entries: Array = []
## True while path following holds the ladder-climbing pose.
var climbing := false


func _init(p_agent: DwarfAgent = null) -> void:
	agent = p_agent


func build() -> void:
	_build_parts()
	_build_collision()
	_build_name_label()
	apply_tints()
	felling_pose = FellingPose.new()
	felling_pose.setup(body,head,hand_l,hand_r,foot_l,foot_r)
	construction_pose = ConstructionPose.new()
	construction_pose.setup(body,head,hand_l,hand_r,foot_l,foot_r)
	mining_pose = MiningPose.new()
	mining_pose.setup(body,head,hand_l,hand_r,foot_l,foot_r)
	carry_pose = CarryPose.new()
	carry_pose.setup(body,head,hand_l,hand_r,foot_l,foot_r)


func reset_part_offsets() -> void:
	climbing = false
	if felling_pose != null:
		felling_pose.reset()
	if mining_pose != null:
		mining_pose.reset()
	if construction_pose != null:
		construction_pose.reset()
	if carry_pose != null:
		carry_pose.reset()
	for part in [body, head, hand_l, hand_r, foot_l, foot_r]:
		if part != null:
			part.position = Vector3.ZERO
			part.rotation = Vector3.ZERO
	relaxed_stance()
	if carry_pose != null and not carried_entries.is_empty():
		carry_pose.hold(carried_entries)


# ── Assembly (doc 41b scene hierarchy) ────────────────────────────────────────

func _build_parts() -> void:
	var appearance := agent.appearance
	if appearance == null:
		push_error("DwarfAgent %d: setup without appearance data." % agent.dwarf_id)
		return

	head = _attach(agent, "MeshHead", DwarfAssets.heads.get(appearance.age_tier))
	body = _attach(agent, "MeshBody", DwarfAssets.body)
	hand_l = _attach(agent, "MeshHandL", DwarfAssets.hand)
	hand_r = _attach(agent, "MeshHandR", DwarfAssets.hand, true)
	foot_l = _attach(agent, "MeshFootL", DwarfAssets.foot)
	foot_r = _attach(agent, "MeshFootR", DwarfAssets.foot, true)
	# Production voxel widths are baked (unit factors); capture the same authored
	# frame in every work/rest rig. Palms and vertical anchors stay intact.
	if body != null: body.scale.x = agent.proportions.body_width
	if head != null: head.scale.x = agent.proportions.head_width
	relaxed_stance()

	if head != null:
		_attach(head, "MeshEyes", DwarfAssets.eyes)
		var hair := DwarfAssets.hair_for(appearance)
		if hair != null:
			_attach(head, "MeshHair", hair)
		if agent.gender == "male" and appearance.beard_style != "":
			var beard: PackedScene = DwarfAssets.beards.get(appearance.beard_style)
			if beard != null:
				_attach(head, "MeshBeard", beard)
		var brows := DwarfAssets.brows_for(appearance)
		if brows != null:
			_attach(head, "MeshBrows", brows)
		# Scar is PORTRAIT-ONLY (doc 41b §Map Mesh vs Portrait) — not added here.


## Instantiates a part GLB under `parent` at identity (shared authoring frame).
## mirror=true flips across X for the right-side hand/foot (doc 41b).
func _attach(parent: Node3D, part_name: String, packed: PackedScene, mirror: bool = false) -> Node3D:
	if packed == null:
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("DwarfAgent: part %s did not instance as Node3D." % part_name)
		return null
	instance.name = part_name
	if mirror:
		instance.scale = Vector3(-1.0, 1.0, 1.0)
		# Preserve the mirrored animation frame without rendering a negatively
		# scaled surface (which reverses its double-sided lighting response).
		var reflection := Transform3D(Basis.from_scale(Vector3(-1,1,1)),Vector3.ZERO)
		for mesh: MeshInstance3D in instance.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null: continue
			mesh.mesh = DwarfAssets.mirrored_limb_mesh(mesh.mesh)
			mesh.transform = mesh.transform * reflection
	parent.add_child(instance)
	ShadowSetup.configure(instance)
	return instance


func _build_collision() -> void:
	# Logical 1x1x3-block box (doc 41 §Visual Mesh Profile) — NOT the 3.3-block
	# visual AABB. Mask 0: nothing physically collides yet (movement is direct
	# until the nav phase decides its sweep model).
	agent.collision_layer = DwarfAgent.COLLISION_LAYER_DWARF
	agent.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "LogicalBox"
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, DwarfAgent.LOGICAL_HEIGHT, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, DwarfAgent.LOGICAL_HEIGHT * 0.5, 0.0)
	agent.add_child(shape)


func _build_name_label() -> void:
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = agent.dwarf_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color(1.0, 0.96, 0.86)
	label.position = Vector3(0.0, 4.0, 0.0)
	label.visible = false   # OFF by default (Alen, 2026-06-10) — DEV toggle in the Dwarves window
	agent.add_child(label)


# ── Tinting (doc 41b §Runtime Tinting — neutral palettes x albedo tint) ───────

func apply_tints() -> void:
	var appearance := agent.appearance
	var skin: Color = DwarfAssets.SKIN_TONES.get(appearance.skin_tone, Color.WHITE)
	var hair: Color = DwarfAssets.HAIR_COLORS.get(appearance.hair_color, Color.WHITE)

	# Body and feet carry baked colours (the tunic torso and leather boots), so
	# tint them WHITE to keep the standard material while leaving
	# the baked colours alone. Skin tint applies to head and hands only.
	_tint(body, Color.WHITE)
	_tint(hand_l, skin)
	_tint(hand_r, skin)
	# The Hearthblock mitten's tunic cuff is a separate baked-cloth mesh (doc 256).
	for hand: Node3D in [hand_l, hand_r]:
		if hand != null: _tint(hand.find_child("cuff", true, false), Color.WHITE)
	# Each dwarf's own tunic colour, on the torso and both cuffs (doc 256); the
	# skin mittens keep their shared mirrored meshes.
	appearance.clothing = DwarfAssets.clothing_for(appearance, agent.dwarf_id)
	for part: Node in [body, hand_l.find_child("cuff", true, false) if hand_l != null else null,
			hand_r.find_child("cuff", true, false) if hand_r != null else null]:
		if part != null: DwarfAssets.dress(part, appearance.clothing)
	_tint(foot_l, Color.WHITE)
	_tint(foot_r, Color.WHITE)
	if head != null:
		# The head mesh itself is skin; children carry their own tints.
		_tint(head, skin, false)
		# Hearthblock bead eyes keep their dark bead and white glint in the world;
		# portraits show the eye colour on the glint (DwarfPortrait, doc 256).
		_tint(head.get_node_or_null("MeshEyes"), Color.WHITE)
		_tint(head.get_node_or_null("MeshHair"), hair)
		_tint(head.get_node_or_null("MeshBeard"), hair)   # beard follows hair colour (doc 41b)
		_tint(head.get_node_or_null("MeshBrows"), hair)


## Applies a tint material to every MeshInstance3D under `node`. Parts are
## authored near-white with baked vertex-colour shading, so albedo_color
## multiplication = the doc-41b tint shader without a custom shader. Material
## settings mirror the project standard (lit per-pixel, double-sided).
func _tint(node: Node, color: Color, recurse_children: bool = true) -> void:
	if node == null:
		return
	if ShadowSetup.is_proxy(node): return
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = color
		mat.roughness = 1.0
		mat.metallic = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_BACK if ShadowSetup.proxy_for_visual(node)!=null else BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		# When tinting the head WITHOUT recursing into part children (they get
		# their own colours), still walk non-part nodes (the GLB's inner scene).
		if not recurse_children and child is Node3D \
				and String(child.name).begins_with("Mesh"):
			continue
		_tint(child, color, recurse_children)


# ── Procedural idle bob (doc 41: transform offsets, no AnimationPlayer) ───────

func idle_bob(bob_phase: float) -> void:
	if body == null:
		return
	relaxed_stance()
	var t := float(Time.get_ticks_msec()) / 1000.0 + bob_phase
	var breathe := sin(t * 2.2) * 0.018
	var sway := sin(t * 1.1) * 0.012
	body.position.y = breathe
	if head != null:
		head.position.y = breathe * 1.4
		head.rotation.y = sway * 0.6
	if hand_l != null:
		hand_l.position.y = relaxed_hand(-1).y + breathe + sin(t * 2.2 + 0.9) * 0.010
	if hand_r != null:
		hand_r.position.y = relaxed_hand(1).y + breathe + sin(t * 2.2 + 2.1) * 0.010
	# Feet stay planted while idle; they animate when walking (nav phase).


## Relaxed hands hang under the sleeves as on the Hearthblock proposal: in, down
## and back from the authored palm, which work poses still grip at (doc 256).
func relaxed_hand(side: int) -> Vector3:
	var proportions := agent.proportions
	return Vector3(side * float(proportions.relaxed_hand_inset), -float(proportions.get("relaxed_hand_drop", 0.0)),
			-float(proportions.get("relaxed_hand_back", 0.0)))


func relaxed_stance() -> void:
	if hand_l != null: hand_l.position = relaxed_hand(-1)
	if hand_r != null: hand_r.position = relaxed_hand(1)
	if foot_l != null: foot_l.position.x = -agent.proportions.relaxed_foot_inset
	if foot_r != null: foot_r.position.x = agent.proportions.relaxed_foot_inset
