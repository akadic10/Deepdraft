extends SceneTree
func _init():
	var light := OmniLight3D.new()
	for p in light.get_property_list():
		if p.name in ["light_size","shadow_blur"]:
			print(p.name," = ",light.get(p.name))
	light.free()
	quit()
