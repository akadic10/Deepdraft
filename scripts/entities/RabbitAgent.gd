extends "res://scripts/entities/GrazerAgent.gd"
## Rabbit art and hopping; shared grazer behavior preserves existing save fields.

func _build_visual(models: Dictionary) -> void:
	var body := (models.body as PackedScene).instantiate() as Node3D
	visual.add_child(body)
	head = Node3D.new()
	head.position = Vector3(0, 0.55, -0.12)
	visual.add_child(head)
	var head_mesh := (models.head as PackedScene).instantiate() as Node3D
	head.add_child(head_mesh)
	head_mesh.position = -head.position
	ears = Node3D.new()
	ears.position = Vector3(0, 0.85, -0.18) - head.position
	head.add_child(ears)
	var ear_mesh := (models.ears as PackedScene).instantiate() as Node3D
	ears.add_child(ear_mesh)
	ear_mesh.position = -head.position - ears.position

func _pose() -> void:
	visual.position.y = sin(hop_progress * PI) * float(definition.navigation.hop_height) if hop_progress < 1 else 0.0
	visual.scale.y = 0.72 if activity == "Sleeping" else 1.0
	head.rotation.x = -0.48 + sin(pose_time * 7) * 0.05 if activity == "Grazing" else -0.16 if activity == "Sleeping" else 0.0
	ears.rotation.x = 0.9 if activity == "Sleeping" else sin(pose_time * 1.4) * 0.045

