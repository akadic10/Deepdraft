from pathlib import Path
p=Path('scripts/entities/DwarfAgent.gd')
s=p.read_text(encoding='utf-8')
a=s.index('## Slow, deep breathing with a drooped head')
b=s.index('# ── DEV interruption helpers',a)
s=s[:a]+s[b:]
a=s.index('## 💤 sleep indicator')
b=s.index('func set_name_label_visible',a)
s=s[:a]+s[b:]
a=s.index('## Distance-driven gait (doc 17')
b=s.index('func _reset_part_offsets()',a)
s=s[:a]+'''## Distance drives the stride so carrying and time controls cannot make feet
## skate. The stance half remains linear; the return half eases into a higher
## arc. Rotations pivot around the part centres, not around the actor's feet.
func _walk_bob(moved: float) -> void:
	_walk_cycle = fposmod(_walk_cycle + moved / maxf(stride_length * 2.0, 0.01), 1.0)
	var amp := stride_length * .5
	_pose_foot(_foot_r,_walk_cycle,amp)
	_pose_foot(_foot_l,fposmod(_walk_cycle+.5,1.0),amp)
	var wave := sin(_walk_cycle*TAU)
	var bounce := (1.0-cos(_walk_cycle*TAU*2.0))*.025
	var lean := deg_to_rad(walk_lean_deg)
	if _body != null:
		_body.rotation = Vector3(lean,wave*.045,-wave*.018)
		var pivot := Vector3(0,1.15,0)
		_body.position = pivot+Vector3(wave*.035,bounce,0)-_body.basis*pivot
	if _head != null:
		_head.rotation = Vector3(lean*.35,-wave*.018,wave*.01)
		var pivot := Vector3(0,2.45,0)
		_head.position = pivot+Vector3(wave*.02,bounce*.65,0)-_head.basis*pivot
	if _hand_l != null: _hand_l.position = Vector3(0,bounce+.025, wave*amp*.75)
	if _hand_r != null: _hand_r.position = Vector3(0,bounce+.025,-wave*amp*.75)


func _pose_foot(foot: Node3D, q: float, amp: float) -> void:
	if foot == null: return
	var forward: float
	var lift := 0.0
	var pitch := 0.0
	if q < .5:
		var phase := q*2.0
		forward = lerpf(-amp,amp,smoothstep(0.0,1.0,phase))
		lift = sin(phase*PI)*_foot_lift
		pitch = -sin(phase*TAU)*.15
	else:
		forward = lerpf(amp,-amp,(q-.5)*2.0)
	var pivot := Vector3(-.5 if foot==_foot_r else .5,0,.15)
	foot.rotation.x = pitch
	foot.position = pivot+Vector3(0,lift,forward)-Basis(Vector3.RIGHT,pitch)*pivot


'''+s[b:]
s=s.replace('and sleeps IN PLACE (no beds yet) for the doc-41 minimum rest, counted in', 'and seeks nearby ground shelter (no beds yet) for the minimum rest, counted in')
s=s.replace('## in place. Local task state', '## beside nearby shelter. Local task state')
p.write_text(s,encoding='utf-8')
