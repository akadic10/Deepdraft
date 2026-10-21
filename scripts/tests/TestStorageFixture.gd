extends RefCounted

## Synthetic container for persistence tests while no player-built storage
## furniture exists. Installed only by test code; never part of the catalogue.
const KEY := "test:furniture:storage"

static func install(controller: Node) -> void:
	controller._defs[KEY] = {
		"furniture_key":KEY,"display_name":"Test storage fixture",
		"description":"Synthetic persistence fixture","furniture_category":"storage",
		"model":"res://assets/models/furniture/packed_furniture.glb",
		"item_key":"base:resources:furniture:log_chair","placement":"floor","yaw_steps":4,
		"footprint":{"width":1,"depth":1},"blocks_movement":true,
		"collision_regions":[{"min":[0,0,0],"max":[1,1,1]}],"room_anchor":false,
		"storage":{"capacity":8,"render_contents":false}}
