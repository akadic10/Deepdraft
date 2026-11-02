extends "res://scripts/components/DwarfWorkToolPose.gd"

## Grilling (doc 290, concept A): a fresh fish pushed onto a peeled green stick. It is carried
## upright to the campfire, held out over the flames while it browns, then held up to the mouth
## and eaten off the stick. The right hand grips the stick at its origin and the left hand up
## it (the work-tool contract). `offset` is the seated body's place (DwarfDining.pose), zero
## standing. All cosmetic: the meal's progress is DwarfFoodBehavior's, and nothing is saved.
## The frames are the concept's (tmp/grill_concepts_20261031): grip, pitch, yaw, the left
## hand's share up the stick (0 leaves it be), and the head's look down.
const POSES := {
	"carry": {"grip": Vector3(-0.42, 1.0, 0.3), "pitch": -6.0, "yaw": 0.0, "support": 0.0, "look": 0.0},
	"hold": {"grip": Vector3(-0.3, 1.2, 0.55), "pitch": 74.0, "yaw": -6.0, "support": 0.8, "look": 0.16},
	"bite": {"grip": Vector3(-0.45, 1.0, 0.9), "pitch": 20.0, "yaw": 25.0, "support": 0.45, "look": 0.06},
}
var _stick: PackedScene


## Poses one frame holding `stick` (the raw or the grilled fish on it); a new stick replaces the
## one in the hand, as the fish browns.
func apply(frame: String, stick: PackedScene, offset: Vector3) -> void:
	if stick == null: return
	if stick != _stick and is_instance_valid(tool):
		tool.free()
		tool = null
	_stick = stick
	if not _ensure_tool(stick, "GrillStick"): return
	tool.visible = true
	var pose: Dictionary = POSES[frame]
	var turn := _orientation(float(pose.pitch), float(pose.yaw))
	var grip: Vector3 = pose.grip + offset
	_pose_hand(_right, grip, turn)
	if float(pose.support) > 0.0:
		_pose_hand(_left, grip + turn * SUPPORT_GRIP * float(pose.support), turn * Quaternion(Vector3.UP, PI))
	if is_instance_valid(_head): _head.rotation = (_rest_rotations[_head] as Vector3) + Vector3(float(pose.look), 0, 0)
