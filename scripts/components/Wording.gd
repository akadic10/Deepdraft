extends RefCounted

## Words for the player (doc 13, "Codes and words"): logic, saves and tests name a state or a
## reason by a code ("grazing", "unknown_material"), and one place turns the code into words
## kept in the feature's own JSON. A sentence is whole, with named fields, so it is never glued
## together from parts:
##   "{count} blocks to copy"
## A sentence that changes with a count gives its forms, chosen by fields.count:
##   {"one": "{count} block to copy", "other": "{count} blocks to copy"}
## Used as: const Wording = preload("res://scripts/components/Wording.gd")
## This is also where a translation would join later (Godot's tr and tr_n).


## `words` with `fields` put in. `words` is a sentence, or its forms by count.
static func fill(words: Variant, fields: Dictionary = {}) -> String:
	var sentence: Variant = words
	if words is Dictionary:
		var forms: Dictionary = words
		sentence = forms.get(form(fields.get("count", 0)), forms.get("other", ""))
	return String(sentence).format(fields)


## The form a count takes: "one" or "other". English has these two.
static func form(count: Variant) -> String:
	return "one" if (count is int or count is float) and is_equal_approx(float(count), 1.0) else "other"


## The words for `code` in a table of them ({code: words}), filled. An unknown code is a
## mistake in the code or the data: it is reported, and the code itself is shown.
static func of(table: Dictionary, code: String, fields: Dictionary = {}) -> String:
	if not table.has(code):
		push_error("Wording: no words for '%s'." % code)
		return code
	return fill(table[code], fields)
