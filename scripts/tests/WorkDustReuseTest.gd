extends "res://scripts/tests/WorkFeedbackTest.gd"

func _run() -> void:
	await _setup_feedback_fixture()
	var original:=GDScript.new()
	original.source_code=FileAccess.get_file_as_string("res://docs/00_dev_roadmap/concepts/events_20261015/WorkDustBurst.gd.before.txt")
	_expect(original.reload()==OK,"frozen dust compiles")
	var latest=load("res://scripts/components/WorkDustBurst.gd")
	var comparisons:=0
	var first_mesh: Mesh
	var first_material: Material
	for profile in [feedback.config.poof,feedback.config.mining.impact,feedback.config.mining.completion]:
		var settings: Dictionary=profile
		if not settings.has("dust_colors"):
			settings=feedback._mining_colors(profile,blocks.get_id("base:terrain:rock:rock01"))
		for seed_value in [7,1234,190,65535]:
			var old: Node3D=original.new()
			var current: Node3D=latest.new()
			for node in [old,current]:
				scene.add_child(node)
				node.setup(settings,1.3,seed_value,20,Vector3.LEFT if seed_value%2==0 else Vector3.ZERO)
			_expect(old._particles==current._particles,"particle generation exactly matches")
			if first_mesh==null:
				first_mesh=current._mesh.multimesh.mesh
				first_material=current._mesh.material_override
			_expect(current._mesh.multimesh.mesh==first_mesh and current._mesh.material_override==first_material,"render resources shared between bursts")
			for step in [0.0,.05,.1,.2,.4]:
				_expect(old.advance(step)==current.advance(step),"expiration unchanged")
				for i in old._mesh.multimesh.instance_count:
					_expect(old._mesh.multimesh.get_instance_transform(i)==current._mesh.multimesh.get_instance_transform(i),"exact animated transform")
					_expect(old._mesh.multimesh.get_instance_color(i)==current._mesh.multimesh.get_instance_color(i),"exact animated color")
				comparisons+=1
			old.free()
			current.free()
	var warmup: MultiMeshInstance3D=latest.create_render_mesh(1)
	_expect(warmup.multimesh.mesh==first_mesh and warmup.material_override==first_material,"warmup uses live mesh and material")
	_expect(warmup.multimesh.instance_count==1 and warmup.multimesh.use_colors,"warmup uses live instance format")
	warmup.free()
	if DisplayServer.get_name()!="headless":
		_expect(is_instance_valid(feedback._dust_warmup) and not feedback._dust_warmup.visible,"scene warms hidden dust")
		_expect(feedback._bursts.is_empty() and burst_events.is_empty(),"warmup emits no live effect or gameplay event")
	feedback.clear_transients()
	_expect(feedback._dust_warmup==null,"cleanup releases warmup")
	for failure in failures: push_error(failure)
	print("WORK_DUST_REUSE_PASS " if failures.is_empty() else "WORK_DUST_REUSE_FAIL ",comparisons," exact poses; ",failures)
	quit(0 if failures.is_empty() else 1)
