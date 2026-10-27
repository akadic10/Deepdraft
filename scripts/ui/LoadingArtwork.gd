extends Control

## One fixed-height panoramic composition: wider screens reveal its sides.
var artwork: Texture2D
var definition: Dictionary = {}
var progress := 0.0
var animation_time := 0.0
var complete := false
var failure := ""
# Text sizes come from the type scale (doc 23, "Type").
const MEDIUM := UITheme.TYPE_MEDIUM

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func source_rect(view_size: Vector2) -> Rect2:
	if artwork == null: return Rect2()
	return band_rect(artwork.get_size(),view_size,float(definition.get("panorama_aspect",32.0/9.0)))

## The part of a panorama a screen shows: a fixed-height band `widest` wide for its height,
## centred, and wider screens reveal its sides. The title screen crops its art the same way.
static func band_rect(tex: Vector2, view_size: Vector2, widest: float) -> Rect2:
	if view_size.y <= 0: return Rect2()
	var aspect := view_size.x / view_size.y
	var height := minf(tex.y,tex.x/maxf(widest,aspect))
	var extent := Vector2(height*aspect,height)
	return Rect2((tex-extent)*.5,extent)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101817"))
	if artwork != null:
		draw_texture_rect_region(artwork,Rect2(Vector2.ZERO,size),source_rect(size))
	# Darken only the lower margin, leaving the concept art clear and vibrant.
	draw_polygon(PackedVector2Array([Vector2(0,size.y*.55),Vector2(size.x,size.y*.55),size,Vector2(0,size.y)]),
		PackedColorArray([Color(0.025,0.035,0.03,0),Color(0.025,0.035,0.03,0),Color(0.025,0.035,0.03,.88),Color(0.025,0.035,0.03,.88)]))
	var scale_factor := clampf(size.y/1080.0,.65,2.0)
	var center := Vector2(size.x*.5,size.y-100*scale_factor)
	draw_set_transform(center,0,Vector2.ONE*scale_factor)
	var ink := Color(String(definition.get("ink","f2eadb")))
	var muted := Color(String(definition.get("muted","c8bda6")))
	var beer := Color(String(definition.get("beer","d89328")))
	var light := Color(String(definition.get("beer_light","f1be57")))
	var foam := Color(String(definition.get("foam","fff0cd")))
	var title_font := UITheme.hearth_title_font()
	var font := UITheme.shared_theme().default_font
	_centered(title_font,String(definition.get("title","DEEPDRAFT")),Vector2(0,-66),MEDIUM.display,ink)
	# An outlined tankard fills bottom-to-top while the slim bar tracks the same work.
	var mug := Rect2(-176,-23,44,53)
	var handle := Rect2(-134,-14,18,31)
	draw_style_box(UITheme.style(Color(0,0,0,.18),muted,3,7,0,0),handle)
	draw_style_box(UITheme.style(Color("202421"),muted,2,5,0,0),mug)
	var interior := mug.grow(-5)
	var fill_height := interior.size.y*clampf(progress,0,1)
	if fill_height>0:
		var fill := Rect2(interior.position+Vector2(0,interior.size.y-fill_height),Vector2(interior.size.x,fill_height))
		draw_rect(fill,beer)
		draw_rect(Rect2(fill.position,Vector2(fill.size.x*.38,fill.size.y)),light)
		for i in range(3):
			var rise := fposmod(animation_time*.24+i*.31,1.0)
			draw_circle(Vector2(fill.position.x+7+i*9,fill.end.y-rise*maxf(0,fill_height-4)),1.2,Color(1,.87,.53,.6))
		if fill_height>3:
			for i in range(6):
				draw_circle(fill.position+Vector2(2+i*5.8,1),3.1,foam)
	draw_line(mug.position+Vector2(7,8),mug.position+Vector2(7,43),Color(1,1,1,.20),1.5,true)
	draw_line(mug.position+Vector2(1,0),mug.position+Vector2(43,0),ink,2,true)
	var label := String(definition.get("ready_label","Your settlement awaits")) if complete else String(definition.get("loading_label","Preparing your settlement"))
	if not failure.is_empty(): label = "%s: %s" % [String(definition.failed_label), failure]
	elif not complete: label += ".".repeat(1+int(animation_time*1.5)%3)
	draw_string(font,Vector2(-98,-7),label,HORIZONTAL_ALIGNMENT_LEFT,-1,17,ink)
	var track := Rect2(-98,8,268,7)
	draw_style_box(UITheme.style(Color(0.05,.07,.06,.75),Color(muted,.35),1,3,0,0),track)
	if progress>0:
		draw_style_box(UITheme.style(beer,light,0,2,0,0),Rect2(track.position+Vector2.ONE,Vector2(266*progress,5)))
	draw_string(font,Vector2(-98,38),"%d%%" % roundi(progress*100),HORIZONTAL_ALIGNMENT_LEFT,-1,13,muted)
	draw_set_transform(Vector2.ZERO)

func _centered(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
