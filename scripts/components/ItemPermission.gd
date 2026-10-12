extends RefCounted

## Permission travels with loose or carried goods, independently of reservation
## and water activity. Accepted storage goods are always colony stock.
static func allowed(node: Node) -> bool:
	return is_instance_valid(node) and not bool(node.get_meta("disallowed", false))

static func action(disallowed: bool) -> Dictionary:
	return {"id":"permission", "text":"Allow" if disallowed else "Disallow",
		"icon":"res://assets/ui/icons/disallow.svg"}
