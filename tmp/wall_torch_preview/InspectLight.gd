extends SceneTree
func _init() -> void:
 var light := OmniLight3D.new()
 for prop in light.get_property_list():
  if 'mask' in String(prop.name):
   print('LIGHT_MASK_PROPERTY ',prop.name, ' = ',light.get(prop.name))
 light.free()
 quit()
