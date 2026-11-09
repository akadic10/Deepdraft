extends RefCounted

## A step up or down (doc 298): the actor still travels in a straight line between waypoints, and
## this draws the feet planted on real floors. The lead foot goes onto the new level, the body follows,
## then the trailing foot comes through. Rising, a foot lifts before it crosses the edge; descending,
## it crosses before it drops. Drawn only: the path, its timing and the actor's position are unchanged.
const LEAD_LANDS := .75      # of the flat distance, just past the block's edge at .5
const LEAD_PLANTS := .5
const TRAIL_PLANTS := .95
const CLEARANCE := .12


static func apply(rig: RefCounted, t: float, rise: int, flat: float, lead_is_right: bool) -> void:
	var up := rise > 0
	var lead: Node3D = rig.foot_r if lead_is_right else rig.foot_l
	var trail: Node3D = rig.foot_l if lead_is_right else rig.foot_r
	var lead_y := smoothstep(0.0,.32,t) if up else smoothstep(.22,.5,t)
	var lead_z := smoothstep(.12,.5,t) if up else smoothstep(0.0,.32,t)
	var trail_y := smoothstep(.5,.78,t) if up else smoothstep(.68,1.0,t)
	var trail_z := smoothstep(.62,1.0,t) if up else smoothstep(.5,.82,t)
	_foot(rig,lead,t,rise,flat,lead_y,lead_z*LEAD_LANDS)
	_foot(rig,trail,t,rise,flat,trail_y,trail_z)
	# The actor rises evenly; the body keeps to the feet, so it pushes up after the lead foot lands.
	var lift := (smoothstep(.15,.85,t)-t)*float(rise)
	var lean := sin(t*PI)*(.16 if up else -.06)
	if rig.body != null:
		rig.body.rotation = Vector3(lean,0,0)
		var pivot := Vector3(0,1.15,0)
		rig.body.position = pivot+Vector3(0,lift,0)-rig.body.basis*pivot
	if rig.head != null:
		rig.head.rotation = Vector3(lean*.5,0,0)
		var pivot := Vector3(0,2.45,0)
		rig.head.position = pivot+Vector3(0,lift,0)-rig.head.basis*pivot
	var swing := sin(t*PI)*.14*(1.0 if lead_is_right else -1.0)
	if rig.hand_l != null: rig.hand_l.position = rig.relaxed_hand(-1)+Vector3(0,lift+.03,swing)
	if rig.hand_r != null: rig.hand_r.position = rig.relaxed_hand(1)+Vector3(0,lift+.03,-swing)


## `gone_up` and `gone_along` say where the foot is in the world, as shares of the step's height and
## flat distance; subtracting the actor's own travel gives the pose.
static func _foot(rig: RefCounted, foot: Node3D, t: float, rise: int, flat: float, gone_up: float, gone_along: float) -> void:
	if foot == null: return
	var arc := sin(gone_up*PI)*CLEARANCE
	var inset: float = rig.agent.proportions.relaxed_foot_inset * (1.0 if foot == rig.foot_r else -1.0)
	foot.rotation = Vector3.ZERO
	foot.position = Vector3(inset,(gone_up-t)*float(rise)+arc,(gone_along-t)*flat)
