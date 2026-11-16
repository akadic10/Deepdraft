extends SceneTree

## Words for the player (scripts/components/Wording.gd; doc 13, "Codes and words"):
## - a sentence takes its named fields, and one with no fields is left as it is;
## - a sentence that changes with a count gives its forms, and the count picks one: "one"
##   for exactly one, "other" for the rest, nought included;
## - a table of words says a code, filled, and an unknown code is reported and shown as the
##   code. The expected error line is listed in tools/test_suite.json.

const Wording = preload("res://scripts/components/Wording.gd")

var failures: Array[String] = []

func _init() -> void: _run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	if not ok: failures.append(description)

func _run() -> void:
	_expect(Wording.fill("Cavern discovered.") == "Cavern discovered.", "a sentence with no fields is left as it is")
	_expect(Wording.fill("{name} is now a {trade}.", {"name": "Valsha", "trade": "Blacksmith"}) == "Valsha is now a Blacksmith.",
		"a sentence takes its named fields")
	var blocks := {"one": "{count} block to copy", "other": "{count} blocks to copy"}
	var said: Array[String] = []
	for count: int in [0, 1, 2, 11]: said.append(Wording.fill(blocks, {"count": count}))
	_expect(said == ["0 blocks to copy", "1 block to copy", "2 blocks to copy", "11 blocks to copy"], "the count picks the form: %s" % [said])
	_expect(Wording.form(1) == "one" and Wording.form(1.0) == "one" and Wording.form(0) == "other" and Wording.form(2) == "other"
		and Wording.form("1") == "other", "only the number one takes the form for one")
	_expect(Wording.fill({"other": "{count} left"}, {"count": 1}) == "1 left", "a sentence with one form uses it for every count")
	var table := {"hurt": "Hurt", "too_large": "at most {across} × {deep}"}
	_expect(Wording.of(table, "hurt") == "Hurt" and Wording.of(table, "too_large", {"across": 32, "deep": 16}) == "at most 32 × 16",
		"a table says a code in its words, filled")
	_expect(Wording.of(table, "missing") == "missing", "an unknown code is shown as the code")
	for failure: String in failures: push_error(failure)
	print("WORDING_OK" if failures.is_empty() else "WORDING_FAIL")
	quit(0 if failures.is_empty() else 1)
