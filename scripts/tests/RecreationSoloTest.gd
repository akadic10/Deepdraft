extends "res://scripts/tests/RudimentaryRecreationTest.gd"

func _run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Solo recreation timed out"); quit(1))
	await _setup_crafting_fixture()
	_create_partner()
	await _solo_and_memory()
	await _distant_partner()
	await _late_partner()
	await _travelling_partner_timeout()
	await _solo_interruption()
	for failure in failures: push_error(failure)
	print("RECREATION_SOLO_OK: solo reward, social upgrade, distant and late partners, cooldown, persistence and interruption" if failures.is_empty() else "RECREATION_SOLO_FAIL")
	quit(0 if failures.is_empty() else 1)

func _alone() -> bool:
	for i in 200:
		await _game_tick()
		if worker.is_recreating() and worker._recreation.playing: return true
	return false

func _finish_game() -> void:
	for i in 400:
		await _game_tick()
		if not worker.is_recreating(): return
	_expect(false,"game completes within its bounded duration")

func _solo_and_memory() -> void:
	_layout(1)
	extra_worker._mood.recreation_retry_hours = 6
	_expect(await _alone(),"one dwarf and one stool can play")
	if not worker.is_recreating(): return
	var game = worker._recreation
	_expect(not game.together and game.describe(worker).activity=="Playing a board game alone","solo play is accurately described")
	game.elapsed = 1
	game._pose(game.players[0])
	var first: Vector3 = worker._hand_r.position
	game.elapsed = 3
	game._pose(game.players[0])
	_expect(first.is_equal_approx(worker._hand_r.position),"solo player takes both turns")
	game.elapsed = 0
	await _finish_game()
	_expect(is_equal_approx(worker._mood.value(),.54) and worker._mood.recreation_memory_hours==0,"solo completion awards four points, never the social bonus")
	_expect(worker._mood.describe().thought.contains("on my own"),"solo happiness thought explains its source")
	_expect(chairs[0].idle_seat_owner<0 and worker.dwarf_id in tasks._idle_dwarves,"solo completion returns the seat and worker")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(worker.serialize_state()))
	worker.restore_saved_runtime(saved)
	_expect(worker._mood.solo_recreation_memory_hours>11 and worker._mood.recreation_retry_hours>5,"solo memory and cooldown survive a JSON roundtrip")
	_expect(not furniture._games.eligible(worker),"completed solo play respects cooldown")
	worker._mood.record_recreation(false)
	_expect(is_equal_approx(worker._mood.value(),.54),"repeating solo play never stacks")
	worker._mood.record_recreation()
	_expect(is_equal_approx(worker._mood.value(),.58),"shared play upgrades the category to eight, not twelve points")
	worker._mood.tick(10)
	worker._mood.record_recreation(false)
	_expect(is_equal_approx(worker._mood.recreation_memory_hours,2) and is_equal_approx(worker._mood.value(),.58),"solo play neither downgrades nor refreshes the stronger social memory")
	worker._mood.tick(3)
	_expect(is_equal_approx(worker._mood.value(),.54),"solo memory remains after the separately earned social thought expires")
	worker._mood.tick(10)
	_expect(is_equal_approx(worker._mood.value(),.5),"both thoughts expire")
	worker._mood.restore({"recreation_memory_hours":8.5,"recreation_retry_hours":2.5})
	_expect(is_equal_approx(worker._mood.value(),.58) and worker._mood.solo_recreation_memory_hours==0,"legacy saves retain their existing shared reward")

func _distant_partner() -> void:
	_layout()
	# A small colony can have an available companion beyond the old 24-block
	# spare-seat radius, as in the player's save. Keep genuine routed movement.
	var rock: int = blocks.get_id("base:terrain:rock:rock01")
	for x in range(40,85):
		for z in range(38,51):
			world.set_block(x,20,z,rock)
			for y in range(21,25): world.set_block(x,y,z,0)
	await _frames(2)
	extra_worker.position = Vector3(78.5,21,44.5)
	extra_worker._idle_behavior.config.start_delay_min_s = 100
	extra_worker._idle_behavior.config.start_delay_max_s = 100
	_expect(chairs.all(func(c): return Vector3(extra_worker.current_cell()-c.origin_cell).length()>24),"partner begins outside both old search radii")
	_expect(await _playing(),"an occupied table recruits the eligible distant companion")
	if not worker.is_recreating(): return
	_expect(worker._recreation.together and worker._recreation.players.size()==2,"both players sit together after routed travel")
	await _finish_game()
	_expect(is_equal_approx(worker._mood.value(),.58) and is_equal_approx(extra_worker._mood.value(),.58),"both participants earn the full shared reward")

func _late_partner() -> void:
	_layout()
	extra_worker._mood.recreation_retry_hours = 6
	_expect(await _alone(),"solo starts before a partner becomes available")
	if not worker.is_recreating(): return
	for i in 80: await _game_tick()
	extra_worker._mood.recreation_retry_hours = 0
	_expect(await _playing(),"an available partner joins an ongoing solo game")
	if not worker.is_recreating(): return
	_expect(worker._recreation.elapsed<.2,"shared play starts a fresh duration after both players settle")
	for i in 150: await _game_tick()
	_expect(worker.is_recreating() and worker._mood.recreation_memory_hours==0,"neither receives a social reward before a full shared game")
	await _finish_game()
	_expect(worker._mood.recreation_memory_hours>11 and extra_worker._mood.recreation_memory_hours>11,"late partner and original player both earn shared happiness")

func _solo_interruption() -> void:
	_layout(1)
	extra_worker._mood.recreation_retry_hours = 6
	_expect(await _alone(),"solo starts before interruption")
	worker.walk_to(Vector3i(43,20,42))
	await _game_tick()
	_expect(not worker.is_recreating() and chairs[0].idle_seat_owner<0,"explicit movement cancels solo and releases the stool")
	_expect(worker._mood.solo_recreation_memory_hours==0 and worker._mood.recreation_memory_hours==0,"partial solo play earns no reward")

func _travelling_partner_timeout() -> void:
	_layout()
	extra_worker._mood.recreation_retry_hours = 6
	_expect(await _alone(),"solo starts before delayed partner travel")
	if not worker.is_recreating(): return
	extra_worker._mood.recreation_retry_hours = 0
	var joined := false
	for i in 400:
		# Keep the invited partner en route, without advancing its actor. Waiting
		# for it must not trap the seated player or award the traveller a game.
		furniture._games.tick(.1)
		worker._process(.1)
		await process_frame
		if worker.is_recreating(): joined = joined or worker._recreation.players.size()==2
		else: break
	_expect(joined and not worker.is_recreating() and not extra_worker.is_recreating(),"an unarrived partner has a bounded wait and releases safely")
	_expect(is_equal_approx(worker._mood.value(),.54) and is_equal_approx(extra_worker._mood.value(),.5),"only the dwarf who actually played receives the solo reward")
	_expect(extra_worker._mood.recreation_retry_hours<1 and extra_worker.dwarf_id in tasks._idle_dwarves,"traveller returns to work with a short retry")
