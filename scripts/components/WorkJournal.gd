extends RefCounted

## Compact saved order identities and diagnostics. Paths, claims, actor states
## and physical progress are deliberately rebuilt from their existing owners.
var next_order := 1
var next_attempt := 1
var now := 0.0
var records: Dictionary = {}
var history: Array[Dictionary] = []
const HISTORY_LIMIT := 200

func ensure(locator: String, label: String) -> String:
	if not records.has(locator):
		records[locator] = {"key":"order:%d" % next_order, "label":label,
			"state":"waiting", "reason":"Waiting for work assessment", "failures":0,
			"last_transition":now}
		next_order += 1
	return String(records[locator].key)

func transition(locator: String, state: String, reason: String, attempt := 0, worker := -1) -> void:
	if not records.has(locator): return
	var record: Dictionary = records[locator]
	if record.state == state and record.reason == reason: return
	record.state = state
	record.reason = reason
	record.last_transition = now
	history.append({"order":record.key,"state":state,"reason":reason,
		"attempt":attempt,"worker":worker,"time":now})
	if history.size() > HISTORY_LIMIT: history.pop_front()

func serialize(live_locators: Array) -> Dictionary:
	var live := {}
	for locator: String in live_locators:
		if records.has(locator): live[locator] = records[locator].duplicate(true)
	return {"next_order":next_order,"next_attempt":next_attempt,"time":now,
		"records":live,"history":history.duplicate(true)}

func restore(saved: Dictionary) -> void:
	next_order = int(saved.get("next_order",1))
	# Never reuse an attempt generation while an old callback can exist.
	next_attempt = maxi(next_attempt,int(saved.get("next_attempt",1)))
	now = float(saved.get("time",0.0))
	records = saved.get("records",{}).duplicate(true)
	history.assign(saved.get("history",[]))
	for locator: String in records:
		transition(locator,"waiting","Restored; revalidating world and supplies")

func prune(live: Array) -> void:
	var retired: Array = records.keys().filter(func(locator: String): return not locator in live)
	retired.sort_custom(func(a: String,b: String): return records[a].last_transition>records[b].last_transition)
	for index in range(HISTORY_LIMIT,retired.size()): records.erase(retired[index])
