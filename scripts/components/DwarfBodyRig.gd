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
const FishingPose = preload("res://scripts/components/DwarfFishingPose.gd")
const GrillPose = preload("res://scripts/components/DwarfGrillPose.gd")
const ShadowSetup = preload("res://scripts/components/VoxelShadowSetup.gd")
const IdleGesture = preload("res://scripts/components/DwarfIdleGesture.gd")

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
var fishing_pose: RefCounted
var grill_pose: RefCounted
## What the hands hold: [[node: Node3D, item_key: String], ...]. The work
## executor owns the pickup/set-down rules; the body only presents the cargo.
var carried_entries: Array = []
## True while path following holds the ladder-climbing pose.
var climbing := false
## How far the body climbs behind the ladder, with less in a shaft that has a wall at the back.
const CLIMB_BACK := .55
const CLIMB_BACK_TIGHT := .15
var _climb_back := -1.0
var _blinking := false
## Crossfade between clips (doc 298). A clip change starts from what was last on screen, and each
## frame's clip writes the true target, which begin_frame restores before the next clip runs, as
## some clips write only part of a pose. Presentation only: nothing here is saved.
const BLEND_SECONDS := .18
const BLEND_LONGEST := .6       # a long way for the body takes longer, such as out of a chair
const BLEND_PER_BLOCK := .35
## A body moving this far with no walk steps there: one foot, then the other, each planted while the
## other moves (doc 298), so a dwarf repositions itself instead of gliding. Drawn only.
const STEP_MIN_GAP := .2
const STEP_LIFT := .18
const STEP_BOB := .035
var _parts: Array[Node3D] = []
var _pivots: Array[Vector3] = []   # each part's visual centre: a fist swings about itself, not the actor's feet
var _rest_bases: Array[Basis] = []
var _blend_from: Array[Transform3D] = []
var _targets: Array[Array] = []   # each part's position, rotation and signed scale, as its clip wrote them
var _shown: Array[Transform3D] = []
var _blend_left := 0.0
var _blend_total := BLEND_SECONDS
var _blend_measured := false
var _blend_steps := false
var _blend_rises := false
const RISE_MIN_GAP := .25
const RISE_LEAN := .22
var _showing_blend := false
## How far an idle dwarf stands back from a wall at its face (doc 298): the head reaches .75 ahead
## of the actor and a wall starts .5 ahead. Drawn only; the actor keeps its cell centre.
const STAND_BACK := .3
const CELL_EDGE := .45
const BREATH := .04
var _stand_back := 0.0
## Work with a tool draws the body back from its target. The dwarf stays there until it next walks,
## rather than sliding forward to its cell centre, into what it built or at what it just worked.
var _work_spot := 0.0


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
	fishing_pose = FishingPose.new()
	fishing_pose.setup(body,head,hand_l,hand_r,foot_l,foot_r)
	grill_pose = GrillPose.new()
	grill_pose.setup(body,head,hand_l,hand_r,foot_l,foot_r)
	var pivots := {body:Vector3(0,1.15,0),head:Vector3(0,2.45,0),hand_l:CarryPose.PALM,hand_r:CarryPose.PALM,
		foot_l:Vector3(.5,.2,.15),foot_r:Vector3(.5,.2,.15)}
	for part in [body,head,hand_l,hand_r,foot_l,foot_r]:
		if part == null: continue
		_parts.append(part)
		_pivots.append(pivots[part])
		_rest_bases.append(part.transform.basis)
	_targets.resize(_parts.size())


## The next frames ease from what is on screen now into whatever the clip writes.
func blend_pose() -> void:
	if _shown.is_empty(): return
	_blend_from = _shown.duplicate()
	_blend_left = BLEND_SECONDS
	_blend_total = BLEND_SECONDS
	_blend_measured = false
	_blend_steps = false


## Before the frame's clip: put back the pose the last clip wrote.
func begin_frame() -> void:
	if _blinking:
		_blinking = false
		agent.get_rest_behavior().blink(false)
	if not _showing_blend: return
	_showing_blend = false
	for i in range(_parts.size()):
		# Signed values, not a transform: a mirrored basis decomposes into three negative scales.
		_parts[i].rotation = _targets[i][1]
		_parts[i].scale = _targets[i][2]
		_parts[i].position = _targets[i][0]


## After the frame's clip: show the mix. `seconds` follows game speed.
func finish_frame(seconds: float) -> void:
	if _blend_left > 0.0:
		if not _blend_measured:
			# The first frame knows the clip's target: this is how far the body has to go.
			_blend_measured = true
			var gap: float = (_blend_from[0]*_pivots[0]).distance_to(_parts[0].transform*_pivots[0])
			_blend_total = clampf(BLEND_SECONDS+gap*BLEND_PER_BLOCK,BLEND_SECONDS,BLEND_LONGEST)
			_blend_left = _blend_total
			var from: Vector3 = _blend_from[0]*_pivots[0]
			var to: Vector3 = _parts[0].transform*_pivots[0]
			_blend_steps = Vector2(from.x-to.x,from.z-to.z).length() >= STEP_MIN_GAP and agent.get_move_path().is_empty() and not climbing
			_blend_rises = to.y-from.y >= RISE_MIN_GAP and not climbing
		_blend_left = maxf(0.0,_blend_left-seconds)
		var elapsed := 1.0-_blend_left/_blend_total
		var weight := smoothstep(0.0,1.0,elapsed)
		if weight < 1.0:
			_showing_blend = true
			for i in range(_parts.size()):
				_targets[i] = [_parts[i].position,_parts[i].rotation,_parts[i].scale]
				var target := _parts[i].transform
				_parts[i].transform = _stepped(i,target,elapsed) if _blend_steps else _mix(i,target,weight)
				if _blend_rises and (_parts[i] == body or _parts[i] == head): _lean_up(i,elapsed)
	_shown.resize(_parts.size())
	for i in range(_parts.size()):
		_shown[i] = _parts[i].transform


## The left foot takes the first half of the move and the right the second; each stays planted while
## the other is up. The body and head rise a little with each step.
func _stepped(index: int, target: Transform3D, elapsed: float) -> Transform3D:
	var part := _parts[index]
	if part == foot_l or part == foot_r:
		var stride := clampf((elapsed if part == foot_l else elapsed-.5)*2.0,0.0,1.0)
		var moved := _mix(index,target,smoothstep(0.0,1.0,stride))
		moved.origin.y += sin(stride*PI)*STEP_LIFT
		return moved
	var mixed := _mix(index,target,smoothstep(0.0,1.0,elapsed))
	if part == body or part == head: mixed.origin.y += absf(sin(elapsed*TAU))*STEP_BOB
	return mixed


## Rising from a chair or the floor, the body leans into it, about its own centre.
func _lean_up(index: int, elapsed: float) -> void:
	var part := _parts[index]
	var pivot := _pivots[index]
	var at := part.transform*pivot
	part.basis = Basis(Vector3.RIGHT,sin(elapsed*PI)*RISE_LEAN)*part.basis
	part.position = at-part.basis*pivot


## Parts carry mirrored or stretched rests, so only the rotation away from the rest is blended.
func _mix(index: int, target: Transform3D, weight: float) -> Transform3D:
	var rest := _rest_bases[index]
	var from := _blend_from[index]
	var a := from.basis*rest.inverse()
	var b := target.basis*rest.inverse()
	if a.determinant() <= 0.0 or b.determinant() <= 0.0: return target
	var turn := a.orthonormalized().get_rotation_quaternion().slerp(b.orthonormalized().get_rotation_quaternion(),weight)
	var basis := Basis(turn)*rest
	var pivot := _pivots[index]
	return Transform3D(basis,(from*pivot).lerp(target*pivot,weight)-basis*pivot)


func reset_part_offsets() -> void:
	blend_pose()
	_showing_blend = false
	var held_back := _stand_back
	_stand_back = 0.0
	climbing = false
	if _work_tool_showing() and not _shown.is_empty():
		_set_work_spot(maxf(-_shown[0].origin.z,0.0))
	elif held_back > 0.0:
		_set_work_spot(held_back)
	if felling_pose != null:
		felling_pose.reset()
	if fishing_pose != null:
		fishing_pose.reset()
	if grill_pose != null:
		grill_pose.reset()
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
	label.font = UITheme.display_font()
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
	idle_pose(float(Time.get_ticks_msec()) / 1000.0 + bob_phase, int(bob_phase * 10.0))


## `t` and `dwarf_seed` choose what the dwarf is doing, so a squad never moves together (doc 298).
func idle_pose(t: float, dwarf_seed: int) -> void:
	if body == null:
		return
	relaxed_stance()
	var gesture := IdleGesture.at(t, dwarf_seed)
	var breathe := sin(t * 1.7) * BREATH
	var shift: float = gesture.shift
	var roll: float = gesture.roll
	_pose_about(body, Vector3(0,1.15,0), Vector3(gesture.lean,0,roll), Vector3(shift,breathe+gesture.rise,0))
	if head != null:
		var look := sin(t * .9) * .05 + float(gesture.look)
		_pose_about(head, Vector3(0,2.45,0), Vector3(gesture.nod,look,-roll*.5+float(gesture.tilt)), Vector3(shift*.8,breathe*1.4+gesture.rise,0))
	for hand in [hand_l, hand_r]:
		if hand == null: continue
		var side := -1 if hand == hand_l else 1
		var relaxed := relaxed_hand(side)
		var at := relaxed+Vector3(shift,breathe+sin(t * 1.7 + side) * .012,0)
		var reach: float = gesture.left_reach if hand == hand_l else gesture.right_reach
		if reach > 0.0:
			var grip: Vector3 = gesture.left_grip if hand == hand_l else gesture.right_grip
			at = at.lerp(grip-hand.transform.basis*CarryPose.PALM,reach)
		hand.position = at
	# Feet stay planted while idle; they animate when walking (nav phase).
	var back := maxf(_work_spot,STAND_BACK if _wall_at_face() else 0.0)
	if back != _stand_back:
		blend_pose()
		_stand_back = back
	var hand_depths := [hand_l.position.z if hand_l != null else 0.0,hand_r.position.z if hand_r != null else 0.0]
	for part in _parts:
		part.position.z = -_stand_back
	if hand_l != null: hand_l.position.z += hand_depths[0]
	if hand_r != null: hand_r.position.z += hand_depths[1]
	if IdleGesture.blinking(t, dwarf_seed):
		_blinking = true
		agent.get_rest_behavior().blink(true)


## Turn a part about its visual centre, not the actor's feet.
func _pose_about(part: Node3D, pivot: Vector3, turn: Vector3, offset: Vector3) -> void:
	part.rotation = turn
	part.position = pivot+offset-part.basis*pivot


## The climb's body offset: behind the ladder, unless a wall stands there.
func climb_back() -> float:
	var back := CLIMB_BACK_TIGHT if _solid_at_head(agent.global_position-agent.global_basis.z*.8) else CLIMB_BACK
	if back != _climb_back:
		if _climb_back >= 0.0: blend_pose()
		_climb_back = back
	return back


func _work_tool_showing() -> bool:
	for pose in [construction_pose,mining_pose,felling_pose]:
		if pose != null and is_instance_valid(pose.tool) and pose.tool.visible: return true
	return false


func _set_work_spot(amount: float) -> void:
	_work_spot = amount
	if carry_pose != null: carry_pose.work_spot = amount


## A walk starts from where the dwarf is drawn: the actor moves back to the drawn spot, unseen, so
## the first step does not pull the body forward to the cell centre and into what it built. It
## crosses into the cell behind only if that cell is walkable. Otherwise it stops at its own cell's
## edge, and the rest eases away as before.
func leave_work_spot() -> void:
	var spot := _work_spot
	_set_work_spot(0.0)
	if spot <= 0.0 or _shown.is_empty(): return
	var amount := clampf(-_shown[0].origin.z,0.0,spot)
	if amount <= 0.0: return
	var behind := agent.global_position-agent.global_basis.z*amount
	var cell := Vector3i(floori(behind.x),agent.current_cell().y,floori(behind.z))
	if cell != agent.current_cell() and not NavGrid.is_walkable(cell): amount = minf(amount,CELL_EDGE)
	# Never leave the actor where navigation cannot walk it back: a walk starts toward its cell
	# centre, and pressed against a block that first step fails and the dwarf stands idle.
	if not NavGrid.line_walkable_flat_from(agent.global_position-agent.global_basis.z*amount,agent.current_cell()): return
	agent.global_position -= agent.global_basis.z*amount
	for i in range(_shown.size()):
		_shown[i].origin.z += amount
	for i in range(_blend_from.size()):
		_blend_from[i].origin.z += amount


## The mirror of leave_work_spot: the walk ended on the drawn spot, and the actor moves unseen to the
## cell centre the job stands on, already facing the work. What is on screen stays put, and the
## crossfade turns the body. The dwarf stays drawn back, so a set-down before the work starts there too.
func arrive_at(center: Vector3, yaw: float) -> void:
	var before := agent.global_transform
	_set_work_spot(Vector2(before.origin.x-center.x,before.origin.z-center.z).length())
	agent.global_position = center
	agent.rotation.y = yaw
	var change: Transform3D = agent.global_transform.affine_inverse()*before
	for i in range(_shown.size()):
		_shown[i] = change*_shown[i]
	for i in range(_blend_from.size()):
		_blend_from[i] = change*_blend_from[i]
	if carry_pose != null and not carried_entries.is_empty(): carry_pose.hold(carried_entries)


## A solid block at head height just ahead, with room behind to stand back into.
func _wall_at_face() -> bool:
	var forward := agent.global_basis.z*.8
	return _solid_at_head(agent.global_position+forward) and not _solid_at_head(agent.global_position-forward)


func _solid_at_head(at: Vector3) -> bool:
	var feet := floori(at.y+.001)
	for y in [feet+1,feet+2]:
		if BlockRegistry.is_solid(WorldData.get_live_block(floori(at.x),y,floori(at.z))): return true
	return false


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
