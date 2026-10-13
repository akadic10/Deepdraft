extends RefCounted

## Furniture owns relocation identity and settings while the actual packed item
## travels through the normal inventory pipeline. Records are not extra items.
var controller: Node
var next_id := 1
var records := {}

func _init(owner: Node) -> void:
	controller = owner

func for_source(installed_id: int) -> String:
	for id: String in records:
		if int(records[id].installed_id) == installed_id: return id
	return ""

func prepare(piece: InstalledFurnitureComponent) -> String:
	var id := "furniture_move:%d" % next_id
	next_id += 1
	records[id] = {"key":piece.furniture_key, "installed_id":piece.installed_id,
		"assigned_dwarf_id":piece.assigned_dwarf_id,
		"storage_filter":piece.storage.serialize_filter() if piece.storage != null else {"tags":[],"items":[],"excluded_items":[]}}
	return id

func cancel(id: String) -> void:
	if not records.has(id): return
	var piece: InstalledFurnitureComponent = controller._installed.get(int(records[id].installed_id))
	if piece != null:
		piece.set_uninstall(false)
		records.erase(id)
	# Once packed, settings travel with the exact item even if its plan is cancelled.

func packed(piece: InstalledFurnitureComponent, cell: Vector3i, worker_id: int) -> bool:
	var id := for_source(piece.installed_id)
	if id.is_empty(): return false
	var record: Dictionary = records[id]
	record.installed_id = -1
	var drops: Node = controller._drop_manager
	var rest_y: int = drops._rest_y(cell + Vector3i.UP)
	drops.restore_loose_item(piece.item_key,Vector3(cell.x+.5,rest_y,cell.z+.5),0,1,id,false,piece.material_id)
	for ghost: FurnitureGhostComponent in controller._ghosts.values():
		if ghost.required_instance_id == id:
			ghost.continuation_worker = worker_id
			ghost.update_lease()
	return true

func installed(id: String, piece: InstalledFurnitureComponent) -> void:
	if not records.has(id) or records[id].key != piece.furniture_key: return
	var record: Dictionary = records[id]
	if piece.storage != null: piece.storage.restore_filter(record.storage_filter)
	var resident := int(record.assigned_dwarf_id)
	# A newer player assignment elsewhere wins while this bed was in transit.
	for other: InstalledFurnitureComponent in controller._installed.values():
		if other != piece and other.assigned_dwarf_id == resident: resident = -1; break
	if resident >= 0: controller.assign_bed(piece.installed_id,resident)
	records.erase(id)

func serialize() -> Dictionary:
	return {"next_id":next_id,"records":records.duplicate(true)}

func restore(data: Dictionary) -> void:
	next_id = int(data.get("next_id",1))
	records = data.get("records",{}).duplicate(true)
