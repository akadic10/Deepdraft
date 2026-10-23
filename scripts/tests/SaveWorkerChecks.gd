extends RefCounted

const Store = preload("res://scripts/components/SaveFileStore.gd")
const Preparation = preload("res://scripts/components/SaveSnapshotPreparation.gd")

class AliasedOwner extends Node:
	var data := {"nested":[{"value":17}]}
	func save_section_key() -> String: return "worker_capture_fixture"
	func serialize_state() -> Dictionary: return data

class FaultStore extends "res://scripts/components/SaveFileStore.gd":
	var fail_write := false
	var fail_read := 0
	var reads := 0
	func _write_text_file(path: String, contents: String) -> String:
		return "injected write failure" if fail_write else super._write_text_file(path,contents)
	func read_snapshot(path: String) -> Dictionary:
		reads+=1
		if reads==fail_read: return {"ok":false,"missing":false,"error":"injected validation failure"}
		return super.read_snapshot(path)

static func run(tree: SceneTree, saves: Node) -> String:
	var expected: Dictionary=saves._build_snapshot()
	var capture: Dictionary=saves._capture_snapshot()
	Preparation.finish(capture,saves._captured_sections)
	if JSON.stringify(expected.scene)!=JSON.stringify(capture.scene): return "worker preparation differs from synchronous serializers"
	var canonical: Dictionary=JSON.parse_string(JSON.stringify(expected))
	var catalogs: Dictionary=saves._capture_catalogs()
	if not Store.Validator.validate_captured(canonical,saves.SAVE_SCHEMA_VERSION,catalogs).is_empty(): return "current snapshot rejected"
	var other_version: Dictionary=canonical.duplicate(true)
	other_version.schema_version=saves.SAVE_SCHEMA_VERSION-1
	if Store.Validator.validate_captured(other_version,saves.SAVE_SCHEMA_VERSION,catalogs).is_empty(): return "a save from another version was accepted"
	var owner:=AliasedOwner.new()
	tree.root.add_child(owner)
	owner.add_to_group("save_state_owner")
	var completions: Array=[]
	var callback:=func(ok: bool): completions.append(ok)
	saves.save_finished.connect(callback)
	if not saves.request_save(): owner.free(); return "async fixture save rejected"
	var same_scene:=tree.current_scene
	if saves.request_save() or saves.request_autosave() or saves.request_load() or saves.request_load_autosave() or saves.request_new_game(): return "overlapping operation accepted"
	if saves.configure_storage_for_testing("user://must_not_switch"): return "storage switched during write"
	if tree.current_scene!=same_scene: return "busy load changed the world"
	owner.data.nested[0].value=99
	if not await _wait(tree,saves): return "async fixture save failed"
	saves.save_finished.disconnect(callback)
	var stored: Dictionary=saves._read_snapshot(saves._save_path)
	owner.free()
	if completions!=[true] or not stored.ok or stored.snapshot.scene.worker_capture_fixture.nested[0].value!=17:
		return "completion or nested snapshot isolation failed"
	# Separate files exercise failure before write, before backup promotion, and
	# validation after primary promotion (which must recover the old primary).
	var directory:=ProjectSettings.globalize_path("user://save_worker_faults")
	var paths: Dictionary={"primary":directory+"/save.json","backup":directory+"/backup.json",
		"temp":directory+"/temp.json","backup_stage":directory+"/backup.tmp.json"}
	for mode in ["write","stage","installed"]:
		for generation in [1,2]:
			var good:=Store.new()
			good.schema_version=2
			good.directory=directory; good.paths=paths; good.catalogs=catalogs.duplicate(true)
			good.snapshot=canonical.duplicate(true); good.snapshot.clock.day=generation
			var task:=WorkerThreadPool.add_task(good.run)
			while not WorkerThreadPool.is_task_completed(task): await tree.process_frame
			WorkerThreadPool.wait_for_task_completion(task)
			if not good.result_error.is_empty(): return "fault fixture setup failed"
		var primary:=FileAccess.get_file_as_bytes(paths.primary)
		var backup:=FileAccess.get_file_as_bytes(paths.backup)
		var fault:=FaultStore.new()
		fault.schema_version=2
		fault.directory=directory; fault.paths=paths; fault.catalogs=catalogs.duplicate(true)
		fault.snapshot=canonical.duplicate(true); fault.snapshot.clock.day=3
		fault.fail_write=mode=="write"
		fault.fail_read=3 if mode=="stage" else (4 if mode=="installed" else 0)
		var task:=WorkerThreadPool.add_task(fault.run)
		while not WorkerThreadPool.is_task_completed(task): await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		if fault.result_error.is_empty() or FileAccess.get_file_as_bytes(paths.primary)!=primary: return "failed transaction changed the last good primary"
		var expected_backup: PackedByteArray=primary if mode=="installed" else backup
		if FileAccess.get_file_as_bytes(paths.backup)!=expected_backup: return "failed transaction lost the valid backup"
	print("SAVE_WORKER_CHECKS_PASS current and other-version validation; exact capture; isolated nested state; busy guards; 3 failure stages")
	return ""

static func _wait(tree: SceneTree,saves: Node) -> bool:
	var start:=Time.get_ticks_msec()
	while saves.is_saving():
		saves._poll_save()
		if Time.get_ticks_msec()-start>30000: return false
		await tree.process_frame
	return bool(saves.last_save_profile.get("success",false))
