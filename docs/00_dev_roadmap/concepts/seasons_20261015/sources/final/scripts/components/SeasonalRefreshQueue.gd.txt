extends RefCounted

## Transient presentation only. Calendar rules commit at midnight; existing art
## catches up over the first night. All owners share a soft main-thread budget.
## No saved jobs or scene references: callbacks re-check the live object by ID.
const FRAME_BUDGET_USEC := 2000
const MAX_ITEMS_PER_OWNER := 4
static var _budget_frame := -1
static var _used_usec := 0
var _keys: Array = []
var _head := 0
var _paced := false
var _calendar := ""
var _clock: Node
var last_work_usec := 0


func begin(keys: Array, clock: Node) -> void:
	_clock = clock
	_keys = keys
	_head = 0
	_calendar = "%d:%s" % [_clock.year, _clock.season]
	_paced = not _clock.restoring_state and _clock.season_visual_progress() < 1.0


func clear() -> void:
	_keys = []
	_head = 0


func pending_count() -> int:
	return _keys.size() - _head


func drain(refresh: Callable) -> void:
	last_work_usec = 0
	if _keys.is_empty(): return
	if _calendar != "%d:%s" % [_clock.year, _clock.season]:
		clear()
		return
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_used_usec = 0
	var due := _keys.size()
	if _paced: due = floori(float(due) * _clock.season_visual_progress())
	var limit := mini(due, _head + MAX_ITEMS_PER_OWNER)
	while _head < limit and _used_usec < FRAME_BUDGET_USEC:
		var started := Time.get_ticks_usec()
		var key: Variant = _keys[_head]
		_head += 1
		refresh.call(key)
		var cost := Time.get_ticks_usec() - started
		_used_usec += cost
		last_work_usec += cost
	if _head == _keys.size(): clear()
