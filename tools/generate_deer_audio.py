"""Original quiet deer breath and leafy chewing foley; no external recordings."""
import numpy as np
from generate_chopping_audio import ROOT, RATE, filtered_noise, write
from generate_rabbit_audio import pulse


def sound(seed, grazing):
    rng = np.random.default_rng(seed)
    duration = .88 if grazing else .62
    t = np.arange(round(duration * RATE)) / RATE
    breath = filtered_noise(rng,len(t),1100)
    leaves = filtered_noise(rng,len(t),3400)
    result = np.zeros_like(t)
    for onset in ([.04,.34,.62] if grazing else [.025,.27]):
        length = rng.uniform(.13,.20)
        envelope = pulse(t,onset+rng.uniform(-.008,.01),length)
        result += envelope * (.55*breath+.45*leaves if grazing else breath)
        if not grazing:
            result += envelope*np.sin(2*np.pi*rng.uniform(155,185)*t)*.12
    result -= result.mean()
    result *= np.minimum(t/.012,1)*np.minimum((duration-t)/.02,1)
    result *= (.32 if grazing else .38)/max(abs(result).max(),.001)
    return result


if __name__ == '__main__':
    sampler=[]
    for kind in ['select','graze']:
        for i in range(3):
            wav=sound(42300+i,kind=='graze')
            path=ROOT/'assets/audio/wildlife'/f'deer_{kind}_{i+1:02}.wav'
            write(path,wav)
            sampler.extend([wav,np.zeros(round(.5*RATE))])
            print(path.name,'peak',round(float(abs(wav).max()),3))
    write(ROOT/'tmp/deer_review/deer_sampler.wav',np.concatenate(sampler))
