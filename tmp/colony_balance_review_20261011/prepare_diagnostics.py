from pathlib import Path
root=Path('P:/Deepdraft')
s=(root/'tmp/personal_bedroom_20261011/diagnostics.cjs').read_text()
s=s.replace("'DwarfRestTest','BedroomTest'","'BedroomPrivacyTest','BedroomComfortTest','ResourceProgressionTest','NavigationRegressionTest','DwarfRestTest','BedroomTest'")
(root/'tmp/colony_balance_review_20261011/diagnostics.cjs').write_text(s)
