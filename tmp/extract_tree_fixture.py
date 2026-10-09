from pathlib import Path
p = Path('P:/Deepdraft/scripts/tests/TreeFellingTest.gd')
s = p.read_text(encoding='utf-8')
start = s.index('\troot.get_node("SaveManager").set_process(false)')
end = s.index('\tvar oak_id :=', start)
fixture = s[start:end]
s = s[:start] + '\t_setup_fixture()\n' + s[end:]
point = s.index('\n\nfunc _test_rectangle_designation')
s = s[:point] + '\n\nfunc _setup_fixture() -> void:\n' + fixture + s[point:]
p.write_text(s, encoding='utf-8')
