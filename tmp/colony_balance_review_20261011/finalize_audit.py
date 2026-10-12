from pathlib import Path
root=Path('P:/Deepdraft')
(root/'scripts/tests/OreFieldIntegrationTest.gd').write_text('''extends "res://scripts/tests/ResourceProgressionTest.gd"

## Milestone 122 deliberately replaces milestone 71's unchanged-abundance target.
## Keep the existing audit entry point on the live eight-seed progression suite.
## Historical comparisons and measurements remain in docs 69–71 and tmp evidence.
''',encoding='utf-8')
p=root/'docs/00_dev_roadmap/122_bedroom_comfort_and_mining_progression.md'
s=p.read_text(encoding='utf-8').replace('Historical abundance-preservation assertions in OreFieldIntegrationTest describe\nmilestone 71. This deliberate progression rebalance supersedes that target.','The OreFieldIntegrationTest entry point now runs ResourceProgressionTest. The\nhistorical abundance-preservation target from milestone 71 is superseded; its\nrecorded comparison data remains available.')
p.write_text(s,encoding='utf-8')
p=root/'tmp/colony_balance_review_20261011/diagnostics.cjs'
s=p.read_text().replace("'BedroomPrivacyTest','BedroomComfortTest'","'OreFieldIntegrationTest','BedroomPrivacyTest','BedroomComfortTest'")
s=s.replace('const wanted =',"for (const name of ['BrazierPreview','HearthAnimationPreview','SmelterPreview','WallTorchPreview']) files.push(root+'/tools/'+name+'.gd');\nconst wanted =")
p.write_text(s)
