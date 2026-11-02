extends RefCounted

## Furniture containers (doc 294) for FurniturePlacementController. A piece whose definition has
## a `storage` block gets a ContainerStorageComponent on install, registered with StockpileManager
## beside the zones. Its goods drop loose in front of it when it goes (uninstalled, moved, its
## wall mined), and they save with it. Its window is the zones' storage window.
const ContainerStore = preload("res://scripts/components/ContainerStorageComponent.gd")
var controller


func _init(owner) -> void:
	controller = owner


func installed(component: InstalledFurnitureComponent) -> void:
	if not component.def.has("storage"): return
	var container = ContainerStore.new()
	container.source_id = TaskManager.allocate_source_id()
	container.setup_container(component.def, component.cells, component.node)
	component.storage = container
	container.window_opener = open_window.bind(component)
	StockpileManager.register_container(container)
	# A save restores furniture before the manager meets the scene's goods.
	if not is_instance_valid(container.drop_manager): container.drop_manager = controller.get_drop_manager()


## Its goods drop in front of it and it leaves the manager. The piece keeps it, so a move's
## record can take its settings along (FurnitureMoves.packed).
func removed(component: InstalledFurnitureComponent) -> void:
	var container = component.storage
	if container == null: return
	container.dump_contents()
	StockpileManager.deregister_container(container)


func save(component: InstalledFurnitureComponent, entry: Dictionary) -> void:
	if component.storage != null: entry["storage"] = component.storage.serialize()


func restore(component: InstalledFurnitureComponent, saved: Dictionary) -> void:
	if component.storage == null or saved.is_empty(): return
	component.storage.restore(saved)
	StockpileManager.rebuild_totals()


## "2 / 3 hooks", "9 / 12 goods": what it holds of what it can.
func holding(component: InstalledFurnitureComponent) -> String:
	return component.storage.usage_text()


## Its window's title: its name, and the one good it keeps when narrowed to one (the owner's
## rule: "Raw materials crate · Iron ore").
func title(component: InstalledFurnitureComponent) -> String:
	var name := CraftMaterials.product_name(component.display_name(), component.material_id)
	var chosen: String = component.storage.chosen_key()
	if chosen.is_empty(): return name
	return "%s · %s" % [name, String(component.storage.drop_manager.get_item_def(chosen).get("display_name", chosen))]


func open_window(component: InstalledFurnitureComponent) -> void:
	var zones: Node = controller.get_tree().get_first_node_in_group("stockpile_controller")
	if zones != null and component.storage != null: zones.open_container_window(component.storage, title(component))
