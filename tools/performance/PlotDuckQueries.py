"""Render the measured duck CPU and whole-frame tails as a standalone figure."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

root = Path(__file__).resolve().parents[2]
output = root / 'docs/00_dev_roadmap/concepts/duck_performance_20261014'
data = json.loads((output / 'comparison.json').read_text(encoding='utf-8'))
phases = ['active_pan', 'active_pan_repeat']
plt.rcParams.update({'font.size': 11, 'axes.spines.top': False, 'axes.spines.right': False})
fig, axes = plt.subplots(1, 2, figsize=(10, 4.7), facecolor='white')
x = np.arange(2)
for ax, metric, statistic, title in [
    (axes[0], 'duck', 'mean', 'Duck processing per frame'),
    (axes[1], 'frame', 'p95', 'Whole-frame P95')]:
    for offset, label, color, caption in [(-.19, 'duck_before_saved', '#6e7c8c', 'Before'),
                                           (.19, 'duck_after_saved', '#147d92', 'After')]:
        values = [data[label][p][metric][statistic] for p in phases]
        bars = ax.bar(x + offset, values, width=.36, color=color, label=caption)
        ax.bar_label(bars, fmt='%.2f', padding=4)
    ax.set_xticks(x, ['First pan', 'Later pan'])
    ax.set_title(title, pad=15)
    ax.set_ylabel('Milliseconds (lower is better)')
    ax.set_ylim(0, ax.get_ylim()[1] * 1.15)
    ax.grid(axis='y', alpha=.18)
    ax.set_axisbelow(True)
axes[0].legend(frameon=False, loc='upper right')
fig.suptitle('Duck navigation query reuse · copied settlement', fontsize=15, y=.98)
fig.text(.5, .02, 'Sequential 12-second samples · 79 animals, 11 ducks · isolated stalls remain', ha='center', fontsize=10)
fig.tight_layout(rect=[0,.06,1,.92])
fig.savefig(output / 'duck_queries.png', dpi=160)
