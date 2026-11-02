extends "res://scripts/tests/WorkerCraftingTest.gd"

## Dwarf health (doc 41 "Health"). Hit points come from Toughness: 100 at Average and 15 a step.
## Health heals a share of the maximum each game hour, faster asleep, never past full, and
## the paused clock stops it. The words are Healthy, Hurt below three quarters and Badly hurt
## below half; Badly hurt brings the Injured thought and the health concern. Nothing takes
## a dwarf below one point. A save keeps the points only while hurt. The character sheet shows
## the line under the level, the bar under Rest and Food, and Toughness's hit points.

const TOUGH := "base:stat:toughness"
var Health: GDScript   # loaded once the autoloads it names are up; a preload here would not compile


func _run() -> void:
	create_timer(150).timeout.connect(func(): push_error("DwarfHealth timeout"); quit(1))
	await _setup_crafting_fixture()
	Health = load("res://scripts/components/DwarfHealth.gd")
	_maximum()
	_healing()
	_words()
	_floor_and_saves()
	await _sheet()
	for failure: String in failures: push_error(failure)
	print("DWARF_HEALTH_OK: maximum, healing, words, floor, saves and sheet" if failures.is_empty() else "DWARF_HEALTH_FAIL")
	quit(0 if failures.is_empty() else 1)


func _average() -> Dictionary:
	var stats := {}
	for id: String in root.get_node("DwarfAssets").stat_ids(): stats[id] = 3
	return stats


## 100 hit points at Average Toughness, 15 a step: 70, 85, 100, 115, 130.
func _maximum() -> void:
	var maxima: Array[int] = []
	for step in range(1, 6):
		var stats := _average()
		stats[TOUGH] = step
		var health = Health.new()
		health.setup(stats)
		maxima.append(int(health.describe().maximum))
		_expect(health.hit_points.full(), "a new dwarf starts full")
	_expect(maxima == [70, 85, 100, 115, 130], "Toughness sets the most hit points: %s" % [maxima])


## 4% of the maximum a game hour asleep, 1% awake, never past full; paused, nothing heals.
func _healing() -> void:
	var health = Health.new()
	health.setup(_average())
	health.hurt(50.0)
	health.clock_tick(1.0, true)
	_expect(is_equal_approx(health.hit_points.current, 54.0), "an hour asleep heals 4 of 100: %.2f" % health.hit_points.current)
	health.clock_tick(1.0, false)
	_expect(is_equal_approx(health.hit_points.current, 55.0), "an hour awake heals 1 of 100: %.2f" % health.hit_points.current)
	health.clock_tick(100.0, true)
	_expect(health.hit_points.full() and is_equal_approx(health.hit_points.current, 100.0), "healing stops at full")
	var clock: Node = root.get_node("WorldClock")
	var was_paused: bool = clock.paused
	clock.set_paused(true)
	worker.get_health().setup(worker.stats, 40.0)
	worker._process(5.0)
	_expect(is_equal_approx(worker.get_health().hit_points.current, 40.0), "the paused clock stops healing")
	clock.set_paused(was_paused)


## Healthy, Hurt below three quarters, Badly hurt below half; Badly hurt brings the Injured
## thought and the health concern, and both go once health is back above half.
func _words() -> void:
	var health = Health.new()
	health.setup(_average())
	var words: Array[String] = []
	for points: float in [100.0, 75.0, 74.0, 50.0, 49.0]:
		health.hit_points.current = points
		words.append(health.word())
	_expect(words == ["Healthy", "Healthy", "Hurt", "Hurt", "Badly hurt"], "the words by the share left: %s" % [words])
	worker.sleep = 1.0
	worker.get_food().value = 1.0
	worker.get_health().setup(worker.stats, 40.0 * worker.get_health().hit_points.maximum / 100.0)
	var injured: Array = worker.get_mood().thoughts().filter(func(thought: Dictionary) -> bool: return thought.id == "injured")
	_expect(injured.size() == 1 and int(injured[0].points) == -8, "Badly hurt brings the Injured thought, −8: %s" % [injured])
	var concern: Dictionary = load("res://scripts/components/DwarfConcern.gd").describe(worker)
	_expect(String(concern.get("kind", "")) == "health" and String(concern.get("title", "")) == "Badly hurt", "Badly hurt is a concern over the head: %s" % concern)
	worker.get_health().setup(worker.stats, 0.6 * worker.get_health().hit_points.maximum)
	_expect(not worker.get_mood().thoughts().any(func(thought: Dictionary) -> bool: return thought.id == "injured"), "above half, the Injured thought is gone")


## Nothing takes a dwarf below one point; a save keeps the points only while hurt, and a
## saved value is held to the dwarf's own range.
func _floor_and_saves() -> void:
	var health = Health.new()
	health.setup(_average())
	var taken: float = health.hurt(500.0)
	_expect(health.hit_points.points() == 1 and is_equal_approx(taken, 99.0), "health stops at one point (took %.1f)" % taken)
	worker.get_health().setup(worker.stats)
	_expect(not worker.serialize_state().has("health"), "a full dwarf saves no health")
	_expect(is_equal_approx(worker.dev_hurt(30.0), 30.0), "DEV: hurt a dwarf takes 30 hit points")
	var saved: Dictionary = worker.serialize_state()
	_expect(saved.has("health") and is_equal_approx(float(saved.health), worker.get_health().hit_points.maximum - 30.0), "a hurt dwarf saves what is left")
	health.setup(_average(), 42.0)
	_expect(is_equal_approx(health.hit_points.current, 42.0), "a saved value comes back")
	health.setup(_average(), 500.0)
	_expect(health.hit_points.full(), "a saved value is held to the dwarf's maximum")


## The sheet: the line under the level, the bar under Rest and Food, and Toughness's hit
## points on the Traits tab.
func _sheet() -> void:
	worker.stats = _average()
	worker.get_health().setup(worker.stats, 70.0)
	var sheet = load("res://scripts/ui/DwarfInspectorPanel.gd").new()
	scene.add_child(sheet)
	await _frames(2)
	sheet.show_data(load("res://scripts/components/DwarfInspection.gd").describe(worker), false)
	await _frames(2)
	_expect(sheet._health_words.text == "Hurt · 70 of 100 hit points", "the line under the level: %s" % sheet._health_words.text)
	_expect(sheet._health_heart.texture != null and root.get_node("UIRegistry").get_need_icon("health") != null, "the heart shows beside the line, the bar and the badges")
	_expect(sheet._health_need.status.text == "70 of 100 · Hurt" and is_equal_approx(sheet._health_need.bar.value, 70.0), "the bar under Rest and Food: %s" % sheet._health_need.status.text)
	var toughness: Dictionary = sheet._stat_rows[TOUGH]
	_expect(String(toughness.effect.text) == "100 hit points; Average is 100", "Toughness gives the hit points: %s" % toughness.effect.text)
	sheet.queue_free()
