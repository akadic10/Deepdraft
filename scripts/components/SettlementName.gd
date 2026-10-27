extends RefCounted

## The settlement's name (doc 23): its rules, and the names the world's seed suggests.
## Autoload-free, so the save validator checks a saved name with the same rules.
## - A name is 3 to 24 characters of letters, spaces, hyphens and apostrophes, and begins
##   with a letter. Spaces at either end go, and a run of spaces becomes one.
## - A suggestion joins a first and a second word part of one style from
##   data/colony/settlement_names.json, which FlagPlacementController reads. The styles take
##   turns, the world's seed picks the parts, and no suggestion repeats an earlier one or
##   stutters at its join, so the same world suggests the same names in the same order.

const MIN_LENGTH := 3
const MAX_LENGTH := 24
const RULE := "Use 3 to 24 letters, spaces, hyphens or apostrophes."
const MARKS := [" ", "-", "'", "’"]


## `text` as the settlement would keep it: its ends trimmed, each run of spaces made one.
static func clean(text: String) -> String:
	return " ".join(text.strip_edges().split(" ", false))


static func is_valid(text: String) -> bool:
	var name := clean(text)
	if name.length() < MIN_LENGTH or name.length() > MAX_LENGTH or not _is_letter(name[0]): return false
	for index in name.length():
		if not _is_letter(name[index]) and not name[index] in MARKS: return false
	return true


## The `index`th name the world `seed` suggests from `styles` (each {"first", "second"}).
static func suggestion(styles: Array, seed: int, index: int) -> String:
	if styles.is_empty(): return ""
	var names: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:settlement" % seed)
	# Draws past the last new name come back round to the first.
	var tries := 0
	while names.size() <= index and tries < (index + 1) * 20:
		tries += 1
		var style: Dictionary = styles[names.size() % styles.size()]
		var first := String(style.first[rng.randi_range(0, style.first.size() - 1)])
		var second := String(style.second[rng.randi_range(0, style.second.size() - 1)])
		if not stutters(first, second) and not first + second in names: names.append(first + second)
	return names[index % names.size()]


## A join that stutters: one letter twice across it ("Skarrok", "Ashhollow"), or one part
## sounding the other again ("Grimrim", "Gungund").
static func stutters(first: String, second: String) -> bool:
	var head := first.to_lower()
	var tail := second.to_lower()
	return head.right(1) == tail.left(1) or head.contains(tail.left(3)) or tail.contains(head.right(3))


static func _is_letter(character: String) -> bool:
	return character.to_lower() != character.to_upper()
