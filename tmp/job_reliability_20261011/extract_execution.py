from pathlib import Path
import re
p=Path('scripts/entities/DwarfAgent.gd')
s=p.read_text(encoding='utf-8')
start=s.index('\tif _task_phase in [TaskPhase.HAUL_PICKUP',s.index('func _process(delta'))
end=s.index('\tif _move_path.is_empty():',start)
block=s[start:end]
block=re.sub(r'\b(_\w+|current_task_id|dwarf_id|rotation|current_cell|is_visible_in_tree)\b',r'agent.\1',block)
block=block.replace('TaskPhase.', 'DwarfAgent.TaskPhase.').replace('FellingPose.', 'DwarfAgent.FellingPose.')
block=block.replace(' * WorldClock.speed','').replace('GENERIC_WORK_TIME','DwarfAgent.GENERIC_WORK_TIME')
block=re.sub(r'\breturn(?=\s*(?:#|\n))','return true',block)
s=s[:start]+'\tif _work_execution.tick(self,delta * WorldClock.speed): return\n'+s[end:]
p.write_text(s,encoding='utf-8')
p=Path('scripts/components/DwarfWorkExecution.gd')
s=p.read_text(encoding='utf-8')
s+='\n## Simulation-time execution dispatch; the agent retains locomotion and poses.\nfunc tick(agent: DwarfAgent, delta: float) -> bool:\n'
s+='\tif agent.current_task_id >= 0 and not TaskManager._matches_attempt(agent.dwarf_id,task_id,generation):\n\t\tagent.abort_task()\n\t\tTaskManager.notify_dwarf_idle(agent.dwarf_id)\n\t\treturn true\n'
s+=block+'\treturn false\n'
p.write_text(s,encoding='utf-8')
