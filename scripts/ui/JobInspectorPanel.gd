extends VBoxContainer

## Development-only view of the shared lifecycle. Reads diagnostics; the single
## explicit retry action releases an attention hold without inventing progress.
var _orders: ItemList
var _detail: RichTextLabel
var _retry: Button
var _rows: Array[Dictionary] = []
var _selected := ""
var _elapsed := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(600,440)
	var caption := Label.new()
	caption.text = "Orders, attempts and waiting conditions"
	add_child(caption)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_orders = ItemList.new()
	_orders.custom_minimum_size = Vector2(235,340)
	_orders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orders.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_orders.item_selected.connect(func(index: int): _selected = _rows[index].key; _show_details())
	body.add_child(_orders)
	_detail = RichTextLabel.new()
	_detail.custom_minimum_size = Vector2(345,340)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.selection_enabled = true
	body.add_child(_detail)
	_retry = UITheme.make_button("Retry selected order","Reassess the current world and supplies.",Vector2(160,28),"dev")
	_retry.pressed.connect(func(): TaskManager.retry_order(_selected); refresh())
	add_child(_retry)
	refresh()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_elapsed += delta
	if _elapsed >= .5:
		_elapsed = 0.0
		refresh()

func refresh() -> void:
	if _orders == null: return
	_rows = TaskManager.job_diagnostics()
	_orders.clear()
	if not _rows.any(func(row: Dictionary): return row.key==_selected): _selected = ""
	for row: Dictionary in _rows:
		_orders.add_item("%s · %s" % [row.key,row.label])
		_orders.set_item_tooltip(_orders.item_count-1,row.reason)
		if row.key == _selected: _orders.select(_orders.item_count-1)
	if _selected.is_empty() and not _rows.is_empty():
		_selected = _rows[0].key
		_orders.select(0)
	_show_details()

func _show_details() -> void:
	_retry.disabled = true
	_detail.text = "No outstanding orders."
	for row: Dictionary in _rows:
		if row.key != _selected: continue
		var lines: Array[String] = ["%s — %s" % [row.key,row.label],String(row.state).capitalize(),row.reason,""]
		if int(row.rejections)>0: lines.append("Workers with rejected routes: %d"%row.rejections)
		for attempt: Dictionary in row.attempts:
			var agent: DwarfAgent = TaskManager.get_agent(int(attempt.worker))
			lines.append("Attempt %d · %s\n%s · %s\nLast progress %.1f seconds ago" % [attempt.attempt,
				agent.dwarf_name if is_instance_valid(agent) else str(attempt.worker),attempt.step,attempt.unit,attempt.seconds_without_progress])
		lines.append("\nRecent transitions")
		for event: Dictionary in row.history:
			lines.append("%.1fs · %s · %s" % [event.time,event.state,event.reason])
		_detail.text = "\n".join(lines)
		_retry.disabled = not row.attempts.is_empty()
		return
