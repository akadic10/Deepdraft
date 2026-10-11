extends RefCounted

## Permission travels with the physical item/stack, independently of ownership,
## reservation and water activity. Default goods are available to the colony.
static func allowed(node: Node) -> bool:
	return is_instance_valid(node) and not bool(node.get_meta("disallowed", false))

static func stack_allowed(stack: Dictionary) -> bool:
	return not bool(stack.get("disallowed", false))

static func action(disallowed: bool) -> Dictionary:
	return {"id":"permission", "text":"Allow" if disallowed else "Disallow",
		"icon":"res://assets/ui/icons/disallow.svg"}
