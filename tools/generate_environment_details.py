"""Recorded weather, wildlife, water and tree creaks.

Uses the first-pass writer/PCM checks without regenerating its accepted sounds.
"""
import json
from generate_environment_audio import REPORT, write


def layer(kind, seconds, seed):
    if kind == "shoreline":
        from generate_water_audio import sound
        write(kind, sound(kind), True)
        return
    if kind in ["rain", "rain_roof"]:
        from generate_rain_thunder_audio import sound
        write(kind, sound(kind), True)
        return
    if kind in ["dry_leaves", "winter_wind"]:
        from generate_wind_foliage_audio import sound
        write(kind, sound(kind), True)
        return
    if kind == "day_insects":
        from generate_insect_audio import sound
        write(kind, sound(kind), True)
        return
    raise ValueError(f"Unknown environmental layer: {kind}")


def detail(kind, index):
    if kind == "drip":
        from generate_water_audio import sound
        write(f"drip_{index:02}", sound(f"drip_{index:02}"))
        return
    if kind in ["thunder", "thunder_near"]:
        from generate_rain_thunder_audio import sound
        write(f"{kind}_{index:02}", sound(f"{kind}_{index:02}"))
        return
    if kind == "wolf_howl":
        from generate_wolf_audio import write_howl
        write_howl(index-1)
        return
    if kind == "frog":
        from generate_frog_audio import sound
        write(f"frog_{index:02}", sound(index-1))
        return
    if kind == "chirp":
        from generate_insect_audio import sound
        write(f"chirp_{index:02}", sound(kind, index-1))
        return
    if kind == "creak":
        from generate_wood_creak_audio import sound
        write(f"creak_{index:02}", sound(index-1))
        return
    raise ValueError(f"Unknown environmental detail: {kind}")


if __name__ == "__main__":
    for i, kind in enumerate(["dry_leaves","winter_wind","day_insects","shoreline","rain","rain_roof"]):
        layer(kind,27+i*2,2101+i*97)
    for kind in ["frog","drip","creak","wolf_howl","thunder","thunder_near","chirp"]:
        for i in range(1,4): detail(kind,i)
    print(json.dumps(REPORT,indent=2))
