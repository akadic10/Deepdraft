extends RefCounted

## Finish private, data-only captures. Never read a scene node or registry here.
static func finish(snapshot: Dictionary, sections: Array[String]) -> void:
	for section in sections:
		match section:
			"water": snapshot.scene[section]=water(snapshot.scene[section])
			"mining": snapshot.scene[section]=mining(snapshot.scene[section])
			"items": snapshot.scene[section]=items(snapshot.scene[section])

static func water(state: Dictionary) -> Dictionary:
	var raw: Dictionary=state.flow
	var cells: Array=[]
	var keys: Array=raw.modified
	keys.sort_custom(_xz_y)
	for key: Vector3i in keys:
		var value:=int(raw.mass.get(key,0))
		if value!=int(raw.initial.get(key,0)): cells.append({"cell":[key.x,key.y,key.z],"units":value})
	var active: Array=[]
	for key: Vector3i in raw.active: active.append([key.x,key.y,key.z])
	var displaced: Array=[]
	for entry: Dictionary in raw.pending:
		var p: Vector3i=entry.point
		displaced.append({"cell":[p.x,p.y,p.z],"units":entry.units})
	state.flow={"cells":cells,"active":active,"displaced":displaced,
		"added_units":raw.added_units,"drained_units":raw.drained_units,"extracted_units":raw.extracted_units}
	var soils: Dictionary=state.moisture
	keys=soils.keys()
	keys.sort_custom(_xz_y)
	var moisture: Array=[]
	for cell: Vector3i in keys:
		var soil: Dictionary=soils[cell]
		moisture.append({"cell":[cell.x,cell.y,cell.z],"value":soil.value,"target":soil.target,"since":soil.since})
	state.moisture=moisture
	return state

static func mining(state: Dictionary) -> Dictionary:
	var keys: Array=state.mined_blocks
	keys.sort_custom(func(a: Vector3i,b: Vector3i): return a.x<b.x or (a.x==b.x and (a.y<b.y or (a.y==b.y and a.z<b.z))))
	var mined: Array=[]
	for p: Vector3i in keys: mined.append([p.x,p.y,p.z])
	var zones: Array=[]
	var ids: Array=state.zones.keys()
	ids.sort()
	for id in ids:
		var blocks: Array=[]
		for p: Vector3i in state.zones[id]: blocks.append([p.x,p.y,p.z])
		zones.append({"id":int(id),"blocks":blocks})
	return {"mined_blocks":mined,"zones":zones}

static func items(state: Dictionary) -> Dictionary:
	state.loose.sort_custom(func(a: Dictionary,b: Dictionary):
		var ak:="%s:%s" % [String(a.item_key),str(a.position)]
		var bk:="%s:%s" % [String(b.item_key),str(b.position)]
		return ak<bk)
	return state

static func _xz_y(a: Vector3i,b: Vector3i) -> bool:
	return a.x<b.x or (a.x==b.x and (a.z<b.z or (a.z==b.z and a.y<b.y)))
