"""Render the retained sequential native scaling measurements."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root=Path(__file__).resolve().parents[2]
out=root/'docs/00_dev_roadmap/concepts/colony_scaling_20261014'
data=json.loads((out/'comparison.json').read_text())
counts=[5,20,50,100]
fig,axes=plt.subplots(1,3,figsize=(14,4.3),layout='constrained')
for version,color in [('before','#b45c49'),('after','#237d94')]:
    for ax,kind,title in zip(axes,['frame','tasks','built'],['Active pan frame P95','TaskManager mean CPU','Blocks constructed']):
        for phase,style in [('active_pan','-'),('active_pan_repeat','--')]:
            values=[]
            for count in counts:
                p=data[f'colony_v2_{version}_{count}'][phase]
                if kind=='frame': value=p['frame']['p95']
                elif kind=='tasks': value=p['processes']['TaskManager']['mean']
                else: value=p['work_after']['built']-p['work_before']['built']
                values.append(value)
            ax.plot(counts,values,style,marker='o',color=color,label=version.title()+(' · later pan' if style=='--' else ' · first pan'))
        ax.set_title(title)
        ax.set_xlabel('Dwarves')
        ax.set_xticks(counts)
        ax.grid(alpha=.2)
        ax.spines[['top','right']].set_visible(False)
        ax.set_ylabel('Milliseconds' if kind!='built' else 'Blocks during phase + warmup')
for ax in axes:
    ax.relim()
    ax.autoscale(enable=True,axis='y')
    ax.set_ylim(bottom=0)
axes[0].legend(fontsize=8)
fig.suptitle('Fixed work yard · 640 initial loose items · 12-second samples\nWhole-game results include different completed work; one sequential pair per population',fontsize=12)
fig.savefig(out/'colony_scaling.png',dpi=160)
print(out/'colony_scaling.png')
