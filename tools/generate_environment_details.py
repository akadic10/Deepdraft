"""Original contextual ambience; seeded synthesis, no external recordings.

Uses the first-pass writer/PCM checks without regenerating its accepted sounds.
"""
import json
import numpy as np
from generate_environment_audio import RATE, REPORT, noise, write


def layer(kind, seconds, seed):
    rng = np.random.default_rng(seed)
    n = seconds * RATE
    t = np.arange(n) / RATE
    channels = []
    for channel in range(2):
        pulse = .65 + .22 * np.sin(2*np.pi*t/seconds*3 + channel)
        if kind == "dry_leaves":
            x = noise(rng,n,1100,6400) * .065 * pulse**2
            x *= .55 + .45 * np.maximum(0,np.sin(2*np.pi*t/seconds*127 + channel))
        elif kind == "winter_wind":
            x = noise(rng,n,160,1100) * .07 * pulse
        elif kind == "day_insects":
            carrier = np.sin(2*np.pi*4210*t + 2*np.sin(2*np.pi*t/seconds*19))
            x = carrier * .045 * np.maximum(0,np.sin(2*np.pi*t/seconds*41))**5
            x += noise(rng,n,3000,6800)*.008*pulse
        elif kind == "shoreline":
            swell = np.maximum(0,np.sin(2*np.pi*t/seconds*8+channel*.7))**2
            x = noise(rng,n,150,1800)*swell*.11 + noise(rng,n,1100,4200)*swell**3*.035
        elif kind == "rain":
            x = noise(rng,n,500,6500)*.105*pulse
            x += noise(rng,n,180,1300)*.025
        else:  # Muffled roof taps, never a bright outdoor hiss indoors.
            x = noise(rng,n,130,1200)*.045*pulse
            for _ in range(seconds*18):
                start = int(rng.uniform(0,n))
                m = int(RATE*.075)
                tt = np.arange(m)/RATE
                tap = np.sin(2*np.pi*rng.uniform(300,850)*tt)*np.exp(-tt*70)*rng.uniform(.015,.05)
                np.add.at(x,(start+np.arange(m))%n,tap)
        channels.append(x)
    write(kind,np.stack(channels,axis=1),True)


def detail(kind, index):
    rng = np.random.default_rng(14170 + index + {"frog":0,"drip":50,"creak":100,"wolf_howl":150,"thunder":200,"chirp":250}[kind])
    duration = {"frog":2.2,"drip":1.8,"creak":2.8,"wolf_howl":6.5,"thunder":10,"chirp":1.4}[kind]
    n = int(RATE*duration)
    t = np.arange(n)/RATE
    x = np.zeros(n)
    if kind == "frog":
        for start in [.15,.62,1.18]:
            u = np.maximum(t-start,0)
            env = np.where(t>=start,np.exp(-u*11)*(1-np.exp(-u*70)),0)
            phase = 2*np.pi*(rng.uniform(260,380)*u + 9*np.sin(2*np.pi*19*u))
            x += (np.sin(phase)+.35*np.sin(2*phase))*.24*env
    elif kind == "drip":
        for start, strength in [(.08,1),(.33,.22),(.62,.1)]:
            u = np.maximum(t-start,0)
            env = np.where(t>=start,(1-np.exp(-u*250))*np.exp(-u*18),0)
            x += np.sin(2*np.pi*(1100*u+65*(1-np.exp(-u*15))))*env*.4*strength
            x += noise(rng,n,800,4200)*env*.04*strength
    elif kind == "creak":
        env = np.sin(np.pi*t/duration)**2
        hz = 130+index*17+75*np.sin(np.pi*t/duration)+6*np.sin(2*np.pi*11*t)
        phase = np.cumsum(hz)*2*np.pi/RATE
        x = (np.sin(phase)+.4*np.sin(phase*3)+noise(rng,n,180,2600)*.3)*env*.12
        x *= .6+.4*np.sin(2*np.pi*27*t)**2
    elif kind == "wolf_howl":
        env = np.sin(np.pi*t/duration)**1.7
        hz = 280+index*18+150*(1-np.exp(-t*3))-135*(t/duration)**3+7*np.sin(2*np.pi*4.5*t)
        phase = np.cumsum(hz)*2*np.pi/RATE
        x = (np.sin(phase)+.22*np.sin(2*phase)+.07*np.sin(3*phase))*env*.22
        x += noise(rng,n,300,1500)*env*.018
    elif kind == "thunder":
        env = (1-np.exp(-t*2))*np.exp(-t*.42)
        swell = .55+.25*np.sin(2*np.pi*.57*t)+.2*np.sin(2*np.pi*1.37*t)
        x = noise(rng,n,35,380)*env*swell*.34
        x += noise(rng,n,180,1100)*np.exp(-((t-1.1)/.55)**2)*.08
    else:
        env = np.sin(np.pi*t/duration)**2*np.maximum(0,np.sin(2*np.pi*(19+index)*t))**5
        x = np.sin(2*np.pi*(3800+index*370)*t)*env*.24
    write(f"{kind}_{index:02}",x)


if __name__ == "__main__":
    for i, kind in enumerate(["dry_leaves","winter_wind","day_insects","shoreline","rain","rain_roof"]):
        layer(kind,27+i*2,2101+i*97)
    for kind in ["frog","drip","creak","wolf_howl","thunder","chirp"]:
        for i in range(1,4): detail(kind,i)
    print(json.dumps(REPORT,indent=2))
