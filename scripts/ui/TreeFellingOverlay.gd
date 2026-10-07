extends Control

## Ground-aligned marquee projected onto the UI canvas. Never intercepts clicks.
var _polygon := PackedVector2Array()
var fill_color := Color(1.0, .65, .2, .16)
var edge_color := Color(1.0, .73, .3, .95)


func set_polygon(points: PackedVector2Array) -> void:
	_polygon = points
	queue_redraw()


func _draw() -> void:
	if _polygon.size() != 4:
		return
	draw_colored_polygon(_polygon, fill_color)
	var edge := _polygon.duplicate()
	edge.append(edge[0])
	draw_polyline(edge, edge_color, 2.0, true)
