class_name SoundGen
extends RefCounted
## Procedural sound effects: everything is synthesized from noise and sine waves at startup,
## so the game ships with zero audio files.

const RATE := 22050


static func to_stream(samples: PackedFloat32Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Short filtered noise burst. Surface changes the tone.
static func footstep(surface: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var params := {
		"grass": {"dur": 0.16, "cut": 0.22, "amp": 0.55, "click": 0.0},
		"sand": {"dur": 0.2, "cut": 0.12, "amp": 0.6, "click": 0.0},
		"rock": {"dur": 0.1, "cut": 0.55, "amp": 0.45, "click": 0.35},
		"snow": {"dur": 0.22, "cut": 0.3, "amp": 0.5, "click": 0.0},
		"water": {"dur": 0.28, "cut": 0.18, "amp": 0.55, "click": 0.0},
	}
	var p: Dictionary = params.get(surface, params.grass)
	var n := int(RATE * p.dur * rng.randf_range(0.85, 1.15))
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var cut: float = p.cut * rng.randf_range(0.8, 1.2)
	var click_f := rng.randf_range(150.0, 260.0)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.006, 1.0) * exp(-t * (18.0 / p.dur) * 0.25)
		var white := rng.randf_range(-1.0, 1.0)
		if surface == "snow" and rng.randf() < 0.04:
			white *= 3.0   # crunch
		lp += (white - lp) * cut
		var s: float = lp * env * p.amp * 2.0
		if p.click > 0.0:
			s += sin(TAU * click_f * t) * exp(-t * 60.0) * p.click
		if surface == "water":
			s *= 0.6 + 0.4 * sin(TAU * 9.0 * t)
		out[i] = s
	return to_stream(out)


## Thump when landing from a jump.
static func land() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		out[i] = (sin(TAU * lerpf(90.0, 45.0, t / 0.22) * t) * 0.6 + lp * 1.5) * exp(-t * 18.0)
	return to_stream(out)


## UI click / hover blip.
static func blip(freq: float, dur := 0.06, amp := 0.25) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * exp(-t * (6.0 / dur)) * amp * minf(t / 0.003, 1.0)
	return to_stream(out)


## Tool hitting wood: hollow knock + bark crunch.
static func chop(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var out := _buf(n)
	var lp := 0.0
	var lp2 := 0.0
	var f := rng.randf_range(120.0, 170.0)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1, 1)
		lp += (w - lp) * 0.35
		lp2 += (lp - lp2) * 0.35
		var band := lp - lp2
		out[i] = (band * 2.2 * exp(-t * 35.0) + sin(TAU * f * t) * 0.7 * exp(-t * 22.0)) * minf(t / 0.002, 1.0)
	return to_stream(out)


## Tool hitting stone: bright ringing partials.
static func clink(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := _buf(n)
	var base := rng.randf_range(780.0, 980.0)
	var partials := [[1.0, 0.5, 18.0], [2.43, 0.3, 26.0], [3.97, 0.22, 34.0], [5.3, 0.12, 45.0]]
	for i in n:
		var t := float(i) / RATE
		var s := rng.randf_range(-1, 1) * exp(-t * 120.0) * 0.6
		for p: Array in partials:
			s += sin(TAU * base * p[0] * t) * p[1] * exp(-t * p[2])
		out[i] = s * 0.55 * minf(t / 0.001, 1.0)
	return to_stream(out)


## Leaves and twigs.
static func rustle(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var out := _buf(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1, 1)
		lp += (w - lp) * 0.5
		var hp := w - lp
		var env := sin(PI * t / 0.32) * (0.6 + 0.4 * rng.randf())
		out[i] = hp * env * 0.55
	return to_stream(out)


## Hitting an animal.
static func thud(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var out := _buf(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.12
		out[i] = (sin(TAU * lerpf(110.0, 60.0, t / 0.2) * t) * 0.8 + lp * 2.0) * exp(-t * 20.0)
	return to_stream(out)


## Swinging a tool through the air.
static func swoosh(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var dur := 0.24
	var n := int(RATE * dur)
	var out := _buf(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		lp += (rng.randf_range(-1, 1) - lp) * lerpf(0.05, 0.4, sin(PI * k))
		out[i] = lp * sin(PI * k) * 1.3
	return to_stream(out)


## A felled tree hitting the ground.
static func tree_fall(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var out := _buf(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.06
		var crackle := (rng.randf_range(-1, 1) if rng.randf() < 0.05 else 0.0) * exp(-t * 4.0) * 0.5
		out[i] = (sin(TAU * 48.0 * t) * 0.9 + lp * 3.0) * exp(-t * 6.0) + crackle
	return to_stream(out)


## Eating: a few crunchy bites.
static func munch(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var out := _buf(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var bite := fmod(t, 0.16) / 0.16
		lp += (rng.randf_range(-1, 1) - lp) * 0.3
		out[i] = lp * exp(-bite * 9.0) * 0.9
	return to_stream(out)


## Creature voices: bleats for grazers, grunts for beasts, squeaks and chirps for small things.
static func creature_call(role: String, size: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	match role:
		"grazer":
			var dur := rng.randf_range(0.4, 0.75)
			var f := rng.randf_range(260.0, 520.0) / sqrt(size)
			var vib := rng.randf_range(5.0, 9.0)
			out = _buf(int(RATE * dur))
			var ph := 0.0
			for i in out.size():
				var t := float(i) / RATE
				ph += TAU * f * (1.0 + 0.04 * sin(TAU * vib * t)) * (1.0 - 0.15 * t / dur) / RATE
				var env := sin(PI * minf(t / dur, 1.0)) * minf(t / 0.03, 1.0)
				out[i] = (sin(ph) * 0.5 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.18) * env * 0.5
		"defensive":
			var dur := rng.randf_range(0.35, 0.6)
			var f := rng.randf_range(70.0, 110.0)
			out = _buf(int(RATE * dur))
			var lp := 0.0
			for i in out.size():
				var t := float(i) / RATE
				lp += (rng.randf_range(-1, 1) - lp) * 0.15
				var pulse := pow(maxf(sin(TAU * f * t), 0.0), 3.0)
				out[i] = (pulse * 0.8 + lp * 1.5) * sin(PI * t / dur) * 0.6
		"critter":
			var dur := 0.12
			out = _buf(int(RATE * dur))
			var f := rng.randf_range(1400.0, 2400.0)
			for i in out.size():
				var t := float(i) / RATE
				out[i] = sin(TAU * f * (1.0 + t * 3.0) * t) * sin(PI * t / dur) * 0.25
		_:  # bird: a few quick chirps
			var chirps := rng.randi_range(2, 4)
			var gap := 0.11
			out = _buf(int(RATE * gap * chirps))
			var f0 := rng.randf_range(2200.0, 3800.0)
			var sweep := rng.randf_range(-0.5, 0.6)
			for i in out.size():
				var t := float(i) / RATE
				var k := fmod(t, gap) / 0.07
				if k < 1.0:
					var f := f0 * (1.0 + sweep * k)
					out[i] = sin(TAU * f * t) * sin(PI * k) * 0.22
	return to_stream(out)


static func _buf(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	return out


## Seamless wind loop: brown noise with slow gusts.
static func wind(seconds := 8.0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var rate := 16000
	var n := int(rate * seconds)
	var raw := _brown(n + rate, rng, 0.02)
	var out := PackedFloat32Array()
	out.resize(n + rate)
	for i in out.size():
		var t := float(i) / rate
		var gust := 0.55 + 0.3 * sin(TAU * t / seconds) + 0.15 * sin(TAU * 3.0 * t / seconds + 1.3)
		out[i] = raw[i] * gust
	return to_stream(_make_loop(out, n, rate), true, rate)


## Seamless ocean loop: low rumble with waves washing in and out.
static func ocean(seconds := 8.0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var rate := 16000
	var n := int(rate * seconds)
	var out := PackedFloat32Array()
	out.resize(n + rate)
	var lp := 0.0
	var lp2 := 0.0
	for i in out.size():
		var t := float(i) / rate
		var swell := pow(0.5 + 0.5 * sin(TAU * 2.0 * t / seconds - 1.2), 2.0)
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * (0.04 + swell * 0.12)
		lp2 += (lp - lp2) * 0.5
		out[i] = lp2 * (0.25 + swell * 0.9) * 2.2
	return to_stream(_make_loop(out, n, rate), true, rate)


static func _brown(n: int, rng: RandomNumberGenerator, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var v := 0.0
	for i in n:
		v = clampf(v * 0.998 + rng.randf_range(-1.0, 1.0) * step, -1.0, 1.0)
		out[i] = v * 2.5
	return out


## Crossfades the extra tail into the start so the loop point is inaudible.
static func _make_loop(src: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	var out := src.slice(0, n)
	for i in fade:
		var a := float(i) / fade
		out[i] = src[i] * a + src[n + i] * (1.0 - a)
	return out
