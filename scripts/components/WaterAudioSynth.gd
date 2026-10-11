extends RefCounted

## Original procedural water: colored turbulence, spray and damped bubbles.
## Built once per process with a private RNG; no assets, simulation RNG or saves.
const RATE := 22050
const SECONDS := 9.0
const OVERLAP := 0.6
static var _cache: Dictionary = {}

static func stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind): return _cache[kind]
	var waterfall := kind=="waterfall"
	var rng := RandomNumberGenerator.new()
	rng.seed = 83173 if waterfall else 39481
	var count := int(RATE*SECONDS)
	var overlap := int(RATE*OVERLAP)
	var wave := PackedFloat32Array()
	wave.resize(count+overlap)
	var low := 0.0
	var mid := 0.0
	var high := 0.0
	var swell := 0.0
	for i in wave.size():
		var noise := rng.randf_range(-1,1)
		low = lerpf(low,noise,0.025)
		mid = lerpf(mid,noise,0.22 if waterfall else 0.12)
		high = lerpf(high,noise,0.62)
		swell = lerpf(swell,rng.randf_range(-1,1),0.00025)
		var body := low*2.2+(mid-low)*0.85+(high-mid)*0.18 if waterfall else low*0.65+(mid-low)*0.48
		wave[i] = body*clampf(1.0+swell*9.0,0.65,1.35)
	# Many overlapping water droplets; the river has a more audible liquid body.
	var at := 0
	while at<wave.size():
		var duration := rng.randf_range(0.025,0.11)
		var length := int(duration*RATE)
		var frequency := rng.randf_range(280,1300)
		var amplitude := rng.randf_range(0.035,0.10) if waterfall else rng.randf_range(0.10,0.24)
		var phase := 0.0
		for j in mini(length,wave.size()-at):
			var t := float(j)/length
			phase += TAU*frequency*(1.0+0.4*t)/RATE
			var envelope := (1.0-exp(-t*50.0))*exp(-t*6.0)*(1.0-t)
			wave[at+j] += sin(phase)*amplitude*envelope
		at += rng.randi_range(260,1300) if waterfall else rng.randi_range(180,950)
	var mixed := PackedFloat32Array()
	mixed.resize(count)
	var energy := 0.0
	var peak := 0.0
	var mean := 0.0
	for i in count:
		var value := wave[i]
		if i<overlap:
			# Equal-power wrap blends continuous tail into head, never silence.
			var phase := float(i)/overlap*PI*0.5
			value = wave[count+i]*cos(phase)+value*sin(phase)
		mixed[i] = value
		energy += value*value
		peak = maxf(peak,absf(value))
		mean += value
	mean /= count
	var scale := minf((0.18 if waterfall else 0.12)/sqrt(energy/count),0.78/(peak+absf(mean)))
	var data := PackedByteArray()
	data.resize(count*2)
	for i in count: data.encode_s16(i*2,roundi((mixed[i]-mean)*scale*32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = count
	sound.data = data
	_cache[kind] = sound
	return sound
