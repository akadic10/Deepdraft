@tool
extends Node

## GLBs contain sibling VoxelVisual / VoxelShadowProxy nodes at the same pivot.
## Add this component under an asset/wrapper for editor + runtime setup, or call
## configure(root) from a loader. World lighting also invokes it automatically.
## It changes instance flags only: shared imported meshes stay immutable.
const VISUAL := &"VoxelVisual"
const PROXY := &"VoxelShadowProxy"
const CASTING_POLICY := &"voxel_shadow_casting"

func _ready() -> void:
	configure(get_parent())

static func is_proxy(mesh: Node) -> bool:
	return mesh is MeshInstance3D and is_part_name(mesh.name, PROXY) and visual_for_proxy(mesh) != null

static func is_part_name(node_name: StringName, role: StringName) -> bool:
	return node_name==role or String(node_name).begins_with(String(role)+"__")

static func visual_for_proxy(proxy: Node) -> MeshInstance3D:
	if proxy.get_parent()==null: return null
	var counterpart := String(proxy.name).replace(String(PROXY),String(VISUAL))
	return proxy.get_parent().get_node_or_null(NodePath(counterpart)) as MeshInstance3D

static func proxy_for_visual(visual: Node) -> MeshInstance3D:
	if visual.get_parent()==null or not is_part_name(visual.name,VISUAL): return null
	var counterpart := String(visual.name).replace(String(VISUAL),String(PROXY))
	return visual.get_parent().get_node_or_null(NodePath(counterpart)) as MeshInstance3D

## Use this for tinting, thumbnails and visible geometry, including a mesh root.
## A shadow-only instance remains visible to Godot's scene tree by design.
static func visual_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D and not is_proxy(root): meshes.append(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if not is_proxy(node): meshes.append(node)
	return meshes

## Persistent instance policy: later world-light binding cannot re-enable a
## ghost's or lamp bracket's caster. Imported shared mesh resources stay intact.
static func set_casting(root: Node, allowed: bool) -> int:
	root.set_meta(CASTING_POLICY, allowed)
	return configure(root)

static func _casting_allowed(node: Node) -> bool:
	while node != null:
		if node.has_meta(CASTING_POLICY) and not bool(node.get_meta(CASTING_POLICY)):
			return false
		node = node.get_parent()
	return true

static func configure(root: Node, enabled := true) -> int:
	var count := 0
	var candidates: Array[Node] = root.find_children("*","MeshInstance3D",true,false)
	if root is MeshInstance3D: candidates.append(root)
	for node in candidates:
		if not is_proxy(node):
			var mesh:=node as MeshInstance3D
			var extras: Dictionary=mesh.get_meta("extras",{})
			if mesh.mesh!=null and extras.is_empty(): extras=mesh.mesh.get_meta("extras",{})
			if not bool(extras.get("voxel_cast_shadow",true)) or not _casting_allowed(mesh):
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
			continue
		var proxy := node as MeshInstance3D
		var visual := visual_for_proxy(proxy)
		if proxy.mesh == null or visual.mesh == null: continue
		var allowed := _casting_allowed(proxy)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if enabled or not allowed else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		proxy.visible = enabled and allowed
		count += 1
	return count
