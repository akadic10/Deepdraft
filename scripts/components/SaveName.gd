extends RefCounted

## A named save's name (doc 23, "The game menu, saving and loading"): its rules, the file it
## is kept in, and the name Save as… suggests. Autoload-free, as SettlementName is.
## - A name is 1 to 40 characters of letters, digits, spaces, commas, hyphens and
##   apostrophes, and begins with a letter or a digit. Spaces at either end go, and a run of
##   spaces becomes one.
## - Capitals don't count when names are compared: "kolgund" is the save "Kolgund".
## - The file is named after the save, as a blueprint's is ("Before the flood" is
##   before_the_flood.json); the name itself is kept inside the file, so any letters work.

const MAX_LENGTH := 40
const RULE := "Use up to 40 letters, digits, spaces, commas, hyphens or apostrophes."
const MARKS := [" ", ",", "-", "'", "’"]
## Names Windows keeps for devices, which no file may take, with an ending or without.
const DEVICES := ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
	"lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]


## `text` as the save would keep it: its ends trimmed, each run of spaces made one.
static func clean(text: String) -> String:
	return " ".join(text.strip_edges().split(" ", false))


static func is_valid(text: String) -> bool:
	var name := clean(text)
	if name.is_empty() or name.length() > MAX_LENGTH or not _is_letter_or_digit(name[0]): return false
	for index in name.length():
		if not _is_letter_or_digit(name[index]) and not name[index] in MARKS: return false
	return true


## What two names are compared by: capitals don't count.
static func key(text: String) -> String:
	return clean(text).to_lower()


## The file a name is kept in, without its ending: "Before the flood" is before_the_flood.
static func stem(text: String) -> String:
	var result := ""
	for character: String in key(text):
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"): result += character
		elif not result.ends_with("_"): result += "_"
	result = result.trim_prefix("_").trim_suffix("_")
	if result.is_empty(): result = "save"
	return result + "_save" if result in DEVICES else result


## The name Save as… suggests: the colony's name and date ("Your colony" before it has a
## name), with a number after it while that name is taken ("Brunhald, autumn day 9, 2").
static func suggestion(colony: String, season: String, day: int, taken: Array) -> String:
	var base := "%s, %s day %d" % [colony if not colony.is_empty() else "Your colony", season.to_lower(), day]
	var keys := taken.map(func(name: Variant) -> String: return key(String(name)))
	var name := base.left(MAX_LENGTH)
	var count := 1
	while key(name) in keys:
		count += 1
		var number := ", %d" % count
		name = base.left(MAX_LENGTH - number.length()) + number
	return name


static func _is_letter_or_digit(character: String) -> bool:
	return character.to_lower() != character.to_upper() or (character >= "0" and character <= "9")
