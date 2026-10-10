"""Original subdued wolf breath/chuff and eating foley, no external samples."""
import numpy as np
from generate_chopping_audio import ROOT, RATE, filtered_noise, write
from generate_rabbit_audio import pulse


def sound(seed, eating):
    rng = np.random.default_rng(seed)
    duration = .8 if eating else .65
    t = np.arange(round(duration*RATE))/RATE
    breath = filtered_noise(rng,len(t),850)
    texture = filtered_noise(rng,len(t),2600)
    result = np.zeros_like(t)
    for onset in ([.03,.3,.54] if eating else [.035,.24]):
        envelope = pulse(t,onset,rng.uniform(.15,.23))
        result += envelope*(.6*breath+.4*texture if eating else breath)
        if not eating:
            tone = rng.uniform(105,125)
            result += envelope*(np.sin(2*np.pi*tone*t)*.14+np.sin(2*np.pi*tone*2*t)*.04)
    result -= result.mean()
    result *= np.minimum(t/.012,1)*np.minimum((duration-t)/.025,1)
    result *= (.28 if eating else .35)/max(abs(result).max(),.001)
    return result


if __name__ == '__main__':
    sampler=[]
    for kind in ['select','eat']:
        for i in range(3):
            wav=sound(77310+i,kind=='eat')
            path=ROOT/'assets/audio/wildlife'/f'wolf_{kind}_{i+1:02}.wav'
            write(path,wav)
            sampler.extend([wav,np.zeros(round(.5*RATE))])
            print(path.name,'peak',round(float(abs(wav).max()),3))
    write(ROOT/'tmp/wolf_review/wolf_sampler.wav',np.concatenate(sampler))
