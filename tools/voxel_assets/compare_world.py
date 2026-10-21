"""Compare matched native migration runs; draw/triangle changes are measured."""
import argparse,json,copy,hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def compare(before,after):
    reports=[]
    for label in (before,after):
        directory=ROOT/'tmp/settlement_art_20261013'/label
        data=json.loads((directory/'report.json').read_text())
        errors=(directory/'run.err').read_text()
        assert not data['failures'],(label,data['failures'])
        assert 'SCRIPT ERROR:' not in errors and 'ERROR:' not in errors,label
        assert not data['quick'],'full run required'
        reports.append(data)
    old,new=reports
    for key in ('resolution','world_fingerprints','detail_identity_sha256','shader_uniform_buffer_slots','fixed_simulation_fps'):
        assert old[key]==new[key],('unmatched fixture',key)
    fixtures=[copy.deepcopy(r['fixture']) for r in reports]
    # Separate shadow nodes intentionally change this rendering count. Every
    # entity, appearance, initial state and logical count must still match.
    mesh_counts=[f['counts'].pop('mesh_instances') for f in fixtures]
    assert fixtures[0]==fixtures[1],'unmatched logical fixture'
    logical_hash=hashlib.sha256(json.dumps(fixtures[0],sort_keys=True).encode()).hexdigest()
    views={}
    for name,a in old['captures'].items():
        b=new['captures'][name]
        for key in ('camera_position','camera_rotation','camera_size','slice_y','sample_frames','warmup_frames','active'):
            assert a[key]==b[key],(name,key)
        row={'active':a['active']}
        for field in ('frame_ms','gpu_ms','render_cpu_ms','scene_process_ms'):
            row[field]={p:{'before':a[field][p],'after':b[field][p],'delta':b[field][p]-a[field][p]} for p in ('p50','p95','p99','max')}
        for field in ('draws','primitives','static_memory_bytes','video_memory_bytes'):
            row[field]={'before':a[field],'after':b[field],'delta':b[field]-a[field]}
        views[name]=row
    return {'labels':[before,after],'conditions':{k:old[k] for k in ('resolution','cpu','adapter','fixed_simulation_fps')},'logical_fixture_sha256':logical_hash,'mesh_instance_counts':mesh_counts,'views':views,
            'save_reload':new['save_reload'],'behavior_observations':new['behavior_observations'],
            'limits':['One hardware configuration; no minimum hardware claim.','Paused samples isolate rendering; wall-budgeted active simulation may diverge despite identical starting state.','Draw counts are measured outcomes: introducing separate proxies can increase draws while reducing caster triangles.','One run per revision; repeat differences near measurement noise.']}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before');parser.add_argument('after');parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); result=compare(args.before,args.after)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    for name,row in result['views'].items():
        gpu=row['gpu_ms']['p50']; frame=row['frame_ms']['p95']
        print(f"{name}: GPU p50 {gpu['before']:.3f} -> {gpu['after']:.3f} ms; frame p95 {frame['before']:.3f} -> {frame['after']:.3f} ms")
    print('VOXEL_WORLD_MATCHED')
