from pathlib import Path
p=Path('P:/Deepdraft/tmp/colony_balance_review_20261011')
s=(p/'ColonyReview.gd').read_text()
s=s.replace('var row := room.duplicate()','var row := room.duplicate()\n\t\trow["with_hearth_c"] = float(room.temp_c)+2400.0/maxf(128,float(room.volume))')
s=s.replace('var data: Dictionary = JSON.parse_string', '''var privacy = load("res://scripts/components/DwarfPrivacy.gd")
	var audtha = tasks._agents[0]
	var before: Vector3 = audtha.global_position
	for i in range(600):
		audtha._idle_behavior.tick(.1)
		if privacy.allowed(audtha.current_cell(),audtha.dwarf_id): break
	report["audtha_exit"] = {"before":str(before),"after":str(audtha.global_position),"permitted":privacy.allowed(audtha.current_cell(),audtha.dwarf_id),"state":audtha._idle_behavior.state}
	var data: Dictionary = JSON.parse_string''')
s=s.replace('report.json','verification.json').replace('COLONY_REVIEW','COLONY_VERIFICATION')
(p/'ColonyVerification.gd').write_text(s)
