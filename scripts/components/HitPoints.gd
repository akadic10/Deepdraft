extends RefCounted

## Hit points (doc 41 "Health"): a maximum and what is left, shared by everything that can be hurt
## or broken. Dwarves use them now; animals will with the Ranger's hunting, and doors with invaders.
## What is left may hold a fraction while healing; readouts show whole points. Nothing ends
## at zero yet: `minimum` holds what is left above it until death and breaking exist.
var maximum := 100.0
var current := 100.0
var minimum := 1.0


## Takes `amount`, never below `minimum`; returns what was taken.
func hurt(amount: float) -> float:
	var before := current
	current = clampf(current - maxf(amount, 0.0), minf(minimum, maximum), maximum)
	return before - current


func heal(amount: float) -> void:
	current = minf(maximum, current + maxf(amount, 0.0))


func full() -> bool:
	return current >= maximum


## What is left as a share of the maximum, 0 to 1.
func share() -> float:
	return current / maximum if maximum > 0.0 else 0.0


## What is left in whole points: a fraction still healing doesn't round up to full.
func points() -> int:
	return floori(current + 0.0001)
