from pathlib import Path
import shutil
root=Path.cwd(); out=root/'tmp/tree_review/godot';(out/'models').mkdir(parents=True,exist_ok=True)
for p in (root/'assets/models/flora/trees').rglob('*.glb'):shutil.copyfile(p,out/'models'/p.name)
for rel in ['body/head_adult','body/body_base','body/eyes','body/hand','body/foot','eyebrows/brows_m_arched','hair/hair_m_short_back','beards/beard_short_trimmed']:
    shutil.copyfile(root/'assets/dwarves'/(rel+'.glb'),out/'models'/(Path(rel).name+'.glb'))
(out/'project.godot').write_text('''config_version=5
[application]
config/name="Deepdraft current tree review"
run/main_scene="res://review.tscn"
[display]
window/size/viewport_width=1600
window/size/viewport_height=900
window/size/window_width_override=1600
window/size/window_height_override=900
[rendering]
renderer/rendering_method="forward_plus"
rendering_device/driver.windows="d3d12"
anti_aliasing/quality/msaa_3d=2
''')
(out/'review.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://TreeReview.gd" id="1"]
[node name="TreeReview" type="Node3D"]
script = ExtResource("1")
''')
(out/'.gitignore').write_text('.godot/\n*.import\n*.uid\n')
