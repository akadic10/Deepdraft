extends RefCounted

## Closed upper/lower parts retain their authored standing coordinates. Only
## the knee pivot moves the lower part; no runtime geometry or scale changes.
static func build(packed: PackedScene, pivot: Vector3, knee_y: float) -> Node3D:
	var leg:=Node3D.new()
	leg.position=pivot
	var asset:=packed.instantiate() as Node3D
	leg.add_child(asset)
	var knee:=Node3D.new()
	knee.name="Knee"
	knee.position.y=knee_y
	leg.add_child(knee)
	var lower:=asset.find_child("Lower",true,false) as Node3D
	if lower!=null:
		# The imported owner is not an ancestor after moving beneath the knee.
		lower.owner=null
		for child in lower.find_children("*","Node",true,false): child.owner=null
		lower.reparent(knee,false)
		lower.position.y=-knee_y
	return leg
