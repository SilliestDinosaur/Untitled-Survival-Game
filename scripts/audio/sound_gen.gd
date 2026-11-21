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


# --- Building blocks --------------------------------------------------------------------------------------------
# Real sounds are layers: a sharp transient (the contact), a body that rings at the material's own frequencies (modes:
# wood knocks low and dull, stone a little higher and short, metal high and long), noise shaped by filters (grit,
# leaves, air), little grains of crackle, and a short tail of the space around. Each sound is made a few times with
# different random numbers, so no two hits are quite alike.

static func _buf(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	return out


static func _noise(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buf(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## An RBJ biquad filter over a whole buffer: "lp" low-pass, "hp" high-pass, "bp" band-pass, at f Hz.
static func _filter(x: PackedFloat32Array, kind: String, f: float, q := 0.707) -> PackedFloat32Array:
	var w0 := TAU * clampf(f, 20.0, RATE * 0.45) / RATE
	var cs := cos(w0)
	var al := sin(w0) / (2.0 * q)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	match kind:
		"lp":
			b0 = (1.0 - cs) * 0.5
			b1 = 1.0 - cs
			b2 = b0
		"hp":
			b0 = (1.0 + cs) * 0.5
			b1 = -(1.0 + cs)
			b2 = b0
		_:
			b0 = al
			b2 = -al
	var a0 := 1.0 + al
	var a1 := -2.0 * cs / a0
	var a2 := (1.0 - al) / a0
	b0 /= a0
	b1 /= a0
	b2 /= a0
	var out := _buf(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var y := b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = y
		out[i] = y
	return out


## Adds `src` times an envelope (amp * exp(-decay * t), with a `attack`-second rise) into out from `at` seconds.
static func _mix(out: PackedFloat32Array, src: PackedFloat32Array, at: float, amp: float, decay: float, attack := 0.001) -> void:
	var o := int(at * RATE)
	for i in src.size():
		var k := o + i
		if k >= out.size():
			break
		var t := float(i) / RATE
		out[k] += src[i] * amp * exp(-decay * t) * minf(t / attack, 1.0)


## A ringing body: damped sine modes [[freq, amp, decay], ...] struck at `at` seconds.
static func _modes(out: PackedFloat32Array, at: float, modes: Array, rng: RandomNumberGenerator) -> void:
	var o := int(at * RATE)
	for m: Array in modes:
		var f: float = m[0]
		var a: float = m[1]
		var d: float = m[2]
		var ph := rng.randf() * TAU
		var len := mini(int(RATE * 6.0 / d), out.size() - o)
		for i in len:
			var t := float(i) / RATE
			out[o + i] += sin(TAU * f * t + ph) * a * exp(-d * t) * minf(t / 0.0006, 1.0)


## Little grains of crackle (twigs, grit, crunch): `count` tiny damped pings at random times from t0 to t1 (thinning
## out toward t1), each between f_lo and f_hi Hz.
static func _grains(out: PackedFloat32Array, rng: RandomNumberGenerator, count: int, t0: float, t1: float, f_lo: float, f_hi: float, amp: float, ping := 0.004) -> void:
	for g in count:
		var at := t0 + (t1 - t0) * pow(rng.randf(), 1.6)
		var f := rng.randf_range(f_lo, f_hi)
		var a := amp * rng.randf_range(0.3, 1.0) * (1.0 - (at - t0) / maxf(t1 - t0, 0.001) * 0.6)
		var o := int(at * RATE)
		var len := mini(int(RATE * ping * 5.0), out.size() - o)
		var ph := rng.randf() * TAU
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		for i in len:
			var t := float(i) / RATE
			out[o + i] += (sin(TAU * f * t + ph) + sgn * rng.randf_range(-0.6, 0.6)) * a * exp(-t / ping)


## A sine whose pitch glides from f0 to f1 over its life (thumps, bubbles, gulps), added at `at`.
static func _glide(out: PackedFloat32Array, at: float, dur: float, f0: float, f1: float, amp: float, decay: float) -> void:
	var o := int(at * RATE)
	var n := mini(int(dur * RATE), out.size() - o)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, pow(t / dur, 0.6))
		ph += TAU * f / RATE
		out[o + i] += sin(ph) * amp * exp(-decay * t) * minf(t / 0.002, 1.0)


## A short tail of the space around (a few combs and an all-pass, lightly mixed in), a soft fade at the end and the
## loudness evened out, then the stream.
static func _finish(out: PackedFloat32Array, wet := 0.12, peak := 0.85) -> AudioStreamWAV:
	if wet > 0.0:
		var src := out.duplicate()
		var delays := [631, 773, 857, 947]   # samples: ~29-43 ms, a small open space
		var wet_sum := _buf(out.size())
		for d: int in delays:
			var buf := _buf(d)
			var idx := 0
			var lp := 0.0
			for i in out.size():
				var y := buf[idx]
				lp = lp * 0.35 + y * 0.65   # the walls soak up the highs
				buf[idx] = src[i] + lp * 0.62
				idx = (idx + 1) % d
				wet_sum[i] += y
		for i in out.size():
			out[i] += wet_sum[i] * wet * 0.25
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	var gain := peak / maxf(top, 0.0001)
	var fade := mini(int(RATE * 0.02), out.size())
	for i in out.size():
		var k := 1.0
		if i > out.size() - fade:
			k = float(out.size() - i) / fade
		out[i] *= gain * k
	return to_stream(out)


# --- Footsteps ---------------------------------------------------------------------------------------------------

## A footstep on a surface: a soft heel thump and the surface's own sound (grass swish, sand grit, stone click,
## snow crunch, water slosh, hollow boards).
static func footstep(surface: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.32))
	var heel := _filter(_noise(int(RATE * 0.12), rng), "lp", rng.randf_range(220.0, 320.0))
	match surface:
		"sand":
			_mix(out, heel, 0.0, 1.2, 30.0, 0.004)
			_mix(out, _filter(_noise(int(RATE * 0.2), rng), "bp", rng.randf_range(1800.0, 2600.0), 0.8), 0.005, 0.35, 16.0, 0.01)
			_grains(out, rng, 22, 0.0, 0.14, 3000.0, 6500.0, 0.06, 0.0015)
		"rock":
			_mix(out, heel, 0.0, 0.8, 45.0, 0.002)
			_modes(out, 0.0, [[rng.randf_range(900.0, 1300.0), 0.12, 90.0], [rng.randf_range(2200.0, 2900.0), 0.06, 120.0]], rng)
			_grains(out, rng, 8, 0.0, 0.09, 2500.0, 6000.0, 0.09, 0.0015)
		"snow":
			_mix(out, heel, 0.0, 0.9, 30.0, 0.008)
			_grains(out, rng, 34, 0.01, 0.16, 900.0, 3200.0, 0.12, 0.003)
		"water":
			_mix(out, _filter(_noise(int(RATE * 0.3), rng), "bp", rng.randf_range(450.0, 700.0), 0.7), 0.0, 1.2, 9.0, 0.03)
			for k in 3:
				_glide(out, rng.randf_range(0.02, 0.15), 0.05, rng.randf_range(350.0, 600.0), rng.randf_range(900.0, 1500.0), 0.12, 50.0)
		"wood":
			_mix(out, heel, 0.0, 0.7, 40.0, 0.002)
			var f := rng.randf_range(160.0, 230.0)
			_modes(out, 0.0, [[f, 0.35, 30.0], [f * 2.4, 0.15, 45.0], [f * 4.1, 0.06, 70.0]], rng)
		_:   # grass
			_mix(out, heel, 0.0, 1.0, 35.0, 0.005)
			_mix(out, _filter(_noise(int(RATE * 0.16), rng), "bp", rng.randf_range(1800.0, 2600.0), 0.9), 0.008, 0.2, 24.0, 0.012)
			_grains(out, rng, 6, 0.0, 0.1, 2500.0, 5000.0, 0.05, 0.002)
	return _finish(out, 0.06, 0.8)


## Landing from a jump or a fall: a body thump and the scuff of grit.
static func land() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var out := _buf(int(RATE * 0.45))
	_glide(out, 0.0, 0.25, 95.0, 48.0, 1.0, 14.0)
	_mix(out, _filter(_noise(int(RATE * 0.3), rng), "lp", 300.0), 0.0, 1.4, 18.0, 0.003)
	_grains(out, rng, 14, 0.01, 0.12, 2000.0, 5000.0, 0.08, 0.002)
	return _finish(out, 0.1, 0.9)


# --- Interface ---------------------------------------------------------------------------------------------------

## A soft wooden tick: buttons and slots.
static func tick(pitch := 1.0, amp := 0.25) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pitch * 1000.0)
	var out := _buf(int(RATE * 0.08))
	_modes(out, 0.0, [[1750.0 * pitch, 0.6, 140.0], [3150.0 * pitch, 0.25, 220.0], [420.0 * pitch, 0.25, 80.0]], rng)
	_mix(out, _filter(_noise(int(RATE * 0.01), rng), "hp", 3000.0), 0.0, 0.3, 500.0)
	return _finish(out, 0.0, amp)


## Kept for callers of the old name.
static func blip(freq: float, dur := 0.06, amp := 0.25) -> AudioStreamWAV:
	return tick(freq / 900.0, amp)


## Something going into your pack: a round "pop" rising in pitch, with a little sparkle.
static func pop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var out := _buf(int(RATE * 0.22))
	_glide(out, 0.0, 0.09, 380.0, 880.0, 0.8, 30.0)
	_mix(out, _filter(_noise(int(RATE * 0.02), rng), "bp", 1500.0, 1.0), 0.0, 0.25, 150.0)
	_modes(out, 0.035, [[1760.0, 0.12, 30.0], [2640.0, 0.06, 40.0]], rng)
	return _finish(out, 0.05, 0.5)


## A panel opening (rising) or closing (falling): a short airy swish and a tick.
static func panel(opening: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23 if opening else 29
	var out := _buf(int(RATE * 0.2))
	var air := _noise(int(RATE * 0.14), rng)
	var swept := _svf_sweep(air, 500.0 if opening else 1800.0, 1800.0 if opening else 500.0, 1.2)
	for i in swept.size():
		swept[i] *= sin(PI * float(i) / swept.size())
	_mix(out, swept, 0.0, 0.35, 0.0)
	_modes(out, 0.11 if opening else 0.0, [[1500.0 if opening else 1100.0, 0.18, 120.0]], rng)
	return _finish(out, 0.05, 0.35)


## Something you can't do: two dull low knocks.
static func error() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var out := _buf(int(RATE * 0.26))
	_modes(out, 0.0, [[220.0, 0.5, 40.0], [440.0, 0.15, 60.0]], rng)
	_modes(out, 0.11, [[175.0, 0.5, 40.0], [350.0, 0.15, 60.0]], rng)
	return _finish(out, 0.0, 0.4)


## A noise swept by a state-variable filter from f0 to f1 (swishes and whooshes).
static func _svf_sweep(x: PackedFloat32Array, f0: float, f1: float, q: float) -> PackedFloat32Array:
	var out := _buf(x.size())
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / q
	for i in x.size():
		var k := float(i) / maxf(x.size() - 1, 1)
		var fc := f0 * pow(f1 / f0, k)
		var f := 2.0 * sin(PI * minf(fc, RATE * 0.2) / RATE)
		low += f * band
		var high := x[i] - low - damp * band
		band += f * high
		out[i] = band
	return out


# --- Gathering, hitting, tools -------------------------------------------------------------------------------------

## An axe or rock into wood: a crisp crack, the trunk's dull knock ringing low, bark crunching off.
static func chop(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.5))
	_mix(out, _filter(_noise(int(RATE * 0.01), rng), "hp", 2000.0), 0.0, 1.0, 400.0)
	var f := rng.randf_range(150.0, 210.0)
	_modes(out, 0.0, [[f, 0.9, 26.0], [f * 2.31, 0.5, 38.0], [f * 3.87, 0.28, 55.0], [f * 5.6, 0.14, 75.0]], rng)
	_glide(out, 0.0, 0.12, 110.0, 70.0, 0.6, 28.0)
	_mix(out, _filter(_noise(int(RATE * 0.15), rng), "bp", rng.randf_range(1900.0, 2600.0), 1.2), 0.002, 0.55, 28.0)
	_grains(out, rng, 10, 0.004, 0.07, 1800.0, 4500.0, 0.14, 0.002)
	return _finish(out, 0.14, 0.9)


## A rock or pick into stone: a hard snap, the stone's short inharmonic ring, a knock low down, grit trickling.
static func clink(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.5))
	_mix(out, _filter(_noise(int(RATE * 0.008), rng), "hp", 2500.0), 0.0, 1.2, 600.0)
	var f := rng.randf_range(620.0, 880.0)
	_modes(out, 0.0, [[f, 0.5, 34.0], [f * 1.83, 0.35, 46.0], [f * 2.67, 0.25, 58.0], [f * 3.9, 0.16, 72.0], [f * 5.1, 0.08, 90.0]], rng)
	_glide(out, 0.0, 0.09, 160.0, 120.0, 0.5, 40.0)
	_grains(out, rng, 16, 0.02, 0.3, 2000.0, 5500.0, 0.1, 0.0018)
	return _finish(out, 0.16, 0.85)


## A pick into ore or crystal: the stone's hit with a bright metallic ring hanging after it.
static func ore_hit(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.9))
	_mix(out, _filter(_noise(int(RATE * 0.008), rng), "hp", 2500.0), 0.0, 1.0, 600.0)
	var f := rng.randf_range(650.0, 850.0)
	_modes(out, 0.0, [[f, 0.4, 36.0], [f * 1.83, 0.28, 48.0], [f * 2.67, 0.2, 60.0]], rng)
	var m := rng.randf_range(1500.0, 2100.0)
	_modes(out, 0.0, [[m, 0.32, 6.0], [m * 2.76, 0.18, 9.0], [m * 5.4, 0.09, 14.0], [m * 8.9, 0.04, 20.0]], rng)
	_grains(out, rng, 12, 0.02, 0.25, 2500.0, 6000.0, 0.08, 0.0015)
	return _finish(out, 0.18, 0.85)


## Into a bush: leaves crinkling, a swish, now and then a twig snapping.
static func rustle(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var dur := 0.45
	var out := _buf(int(RATE * dur))
	var swish := _filter(_noise(int(RATE * 0.35), rng), "bp", rng.randf_range(1600.0, 2400.0), 0.7)
	for i in swish.size():
		swish[i] *= sin(PI * float(i) / swish.size())
	_mix(out, swish, 0.0, 0.45, 2.0, 0.01)
	_grains(out, rng, 45, 0.0, 0.35, 2000.0, 6000.0, 0.16, 0.0025)
	if rng.randf() < 0.45:
		var at := rng.randf_range(0.03, 0.12)
		_mix(out, _filter(_noise(int(RATE * 0.01), rng), "hp", 1500.0), at, 0.7, 300.0)
		_modes(out, at, [[rng.randf_range(500.0, 800.0), 0.25, 60.0], [rng.randf_range(1500.0, 2000.0), 0.12, 90.0]], rng)
	return _finish(out, 0.1, 0.75)


## Hitting an animal: a deep body blow, a muffled thump and a wet slap.
static func thud(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.4))
	_glide(out, 0.0, 0.22, rng.randf_range(85.0, 105.0), 50.0, 1.0, 16.0)
	_mix(out, _filter(_noise(int(RATE * 0.2), rng), "lp", rng.randf_range(300.0, 450.0)), 0.0, 1.4, 22.0, 0.002)
	_mix(out, _filter(_noise(int(RATE * 0.06), rng), "bp", rng.randf_range(800.0, 1100.0), 1.8), 0.002, 0.5, 55.0)
	return _finish(out, 0.1, 0.9)


## A tool swung through the air: a whoosh that rises and falls with the swing.
static func swoosh(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var dur := rng.randf_range(0.22, 0.3)
	var out := _buf(int(RATE * (dur + 0.05)))
	var air := _noise(int(RATE * dur), rng)
	var peak_f := rng.randf_range(1400.0, 2000.0)
	var half := int(air.size() * 0.55)
	var up := _svf_sweep(air.slice(0, half), 350.0, peak_f, 1.6)
	var down := _svf_sweep(air.slice(half), peak_f, 600.0, 1.6)
	up.append_array(down)
	for i in up.size():
		up[i] *= pow(sin(PI * float(i) / up.size()), 1.5)
	_mix(out, up, 0.0, 0.7, 0.0)
	return _finish(out, 0.04, 0.55)


## A tool giving out: a sharp crack, splintering, bits clattering down.
static func tool_break(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.9))
	_mix(out, _filter(_noise(int(RATE * 0.02), rng), "hp", 1800.0), 0.0, 1.2, 150.0)
	_modes(out, 0.0, [[420.0, 0.5, 30.0], [1130.0, 0.3, 45.0], [2400.0, 0.2, 60.0]], rng)
	_grains(out, rng, 20, 0.005, 0.12, 1500.0, 4500.0, 0.25, 0.003)
	for k in 4:   # pieces landing
		var at := 0.18 + k * rng.randf_range(0.08, 0.14)
		var f := rng.randf_range(1200.0, 2400.0)
		_modes(out, at, [[f, 0.25 / (k + 1), 25.0], [f * 2.7, 0.12 / (k + 1), 35.0]], rng)
	return _finish(out, 0.15, 0.85)


## Being hurt: a heavy blow to the body and the breath knocked out.
static func hurt(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.45))
	_glide(out, 0.0, 0.2, 120.0, 55.0, 1.0, 18.0)
	_mix(out, _filter(_noise(int(RATE * 0.12), rng), "lp", 500.0), 0.0, 1.2, 30.0)
	var puff := _filter(_noise(int(RATE * 0.2), rng), "bp", rng.randf_range(700.0, 1000.0), 1.4)
	for i in puff.size():
		puff[i] *= sin(PI * float(i) / puff.size())
	_mix(out, puff, 0.06, 0.45, 6.0, 0.02)
	return _finish(out, 0.08, 0.8)


## A felled tree: the trunk creaking as it goes, then the crash, branches cracking, leaves rushing, the ground
## shaking under it.
static func tree_fall(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 2.6))
	# The creak: a stick-slip sawtooth wandering in pitch, through the wood's resonance.
	var creak := _buf(int(RATE * 0.8))
	var ph := 0.0
	var f := 85.0
	for i in creak.size():
		f = clampf(f + rng.randf_range(-2.5, 2.5), 60.0, 140.0)
		ph = fmod(ph + f / RATE, 1.0)
		var t := float(i) / creak.size()
		creak[i] = (ph * 2.0 - 1.0) * t * t
	_mix(out, _filter(creak, "bp", 650.0, 2.5), 0.0, 1.4, 0.0, 0.2)
	var hit := 0.85
	_glide(out, hit, 0.9, 62.0, 34.0, 1.0, 4.5)
	_mix(out, _filter(_noise(int(RATE * 1.5), rng), "lp", 180.0), hit, 2.0, 3.2, 0.005)
	var leaves := _filter(_noise(int(RATE * 1.2), rng), "bp", 1700.0, 0.7)
	_mix(out, leaves, hit - 0.05, 0.4, 3.0, 0.08)
	_grains(out, rng, 90, hit, hit + 0.9, 900.0, 4000.0, 0.35, 0.004)
	return _finish(out, 0.22, 0.95)


## Eating: a few crunchy bites and chewing.
static func munch(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.6))
	for b in 3:
		var at := b * rng.randf_range(0.15, 0.19)
		_grains(out, rng, 22, at, at + 0.05, 1500.0, 4500.0, 0.3, 0.003)
		_mix(out, _filter(_noise(int(RATE * 0.08), rng), "lp", 350.0), at, 0.6, 30.0, 0.005)
	return _finish(out, 0.04, 0.6)


## Drinking: two gulps.
static func gulp(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.55))
	for k in 2:
		var at := k * 0.24
		_glide(out, at, 0.12, rng.randf_range(260.0, 320.0), 120.0, 0.8, 18.0)
		_mix(out, _filter(_noise(int(RATE * 0.06), rng), "lp", 600.0), at, 0.4, 40.0)
	return _finish(out, 0.03, 0.6)


# --- Crafting and building -----------------------------------------------------------------------------------------

## Something finished: a warm two-note bell (the root, then the fifth above).
static func chime() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var out := _buf(int(RATE * 1.4))
	for k in 2:
		var f := 523.25 * (1.5 if k == 1 else 1.0)
		_modes(out, k * 0.11, [[f, 0.5, 3.0], [f * 2.0, 0.25, 4.5], [f * 2.76, 0.14, 6.0], [f * 5.4, 0.06, 9.0]], rng)
	return _finish(out, 0.2, 0.5)


## A wooden piece set down: a hollow plank knock.
static func place_wood(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.5))
	var f := rng.randf_range(190.0, 250.0)
	_modes(out, 0.0, [[f, 0.8, 18.0], [f * 2.1, 0.4, 28.0], [f * 3.4, 0.2, 40.0], [f * 4.7, 0.1, 55.0]], rng)
	_glide(out, 0.0, 0.15, 100.0, 60.0, 0.6, 22.0)
	_mix(out, _filter(_noise(int(RATE * 0.05), rng), "bp", 2000.0, 1.0), 0.0, 0.3, 60.0)
	return _finish(out, 0.16, 0.85)


## A stone piece set down: a heavy thud and a scrape of grit.
static func place_stone(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.55))
	_glide(out, 0.0, 0.25, 85.0, 45.0, 1.0, 14.0)
	_mix(out, _filter(_noise(int(RATE * 0.2), rng), "lp", 400.0), 0.0, 1.2, 20.0)
	var f := rng.randf_range(380.0, 520.0)
	_modes(out, 0.0, [[f, 0.3, 40.0], [f * 1.9, 0.18, 55.0], [f * 2.8, 0.1, 70.0]], rng)
	_grains(out, rng, 18, 0.01, 0.2, 2000.0, 5000.0, 0.1, 0.002)
	return _finish(out, 0.16, 0.9)


## A hammer on wood: the knock and a short ring of the head.
static func hammer(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.45))
	_mix(out, _filter(_noise(int(RATE * 0.006), rng), "hp", 2500.0), 0.0, 1.0, 700.0)
	var f := rng.randf_range(200.0, 260.0)
	_modes(out, 0.0, [[f, 0.7, 24.0], [f * 2.3, 0.35, 35.0], [f * 3.9, 0.18, 50.0]], rng)
	var m := rng.randf_range(2300.0, 2800.0)
	_modes(out, 0.0, [[m, 0.2, 22.0], [m * 2.6, 0.08, 30.0]], rng)
	return _finish(out, 0.12, 0.85)


## A door swinging: a creaking hinge and the latch at the end.
static func creak(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var dur := rng.randf_range(0.45, 0.65)
	var out := _buf(int(RATE * (dur + 0.2)))
	var src := _buf(int(RATE * dur))
	var ph := 0.0
	var f := rng.randf_range(100.0, 150.0)
	for i in src.size():
		f = clampf(f + rng.randf_range(-3.0, 3.2), 80.0, 220.0)
		ph = fmod(ph + f / RATE, 1.0)
		src[i] = (ph * 2.0 - 1.0) * sin(PI * float(i) / src.size())
	_mix(out, _filter(src, "bp", rng.randf_range(700.0, 950.0), 3.0), 0.0, 1.0, 0.0)
	_mix(out, _filter(src, "bp", rng.randf_range(1500.0, 1900.0), 4.0), 0.0, 0.5, 0.0)
	_modes(out, dur, [[rng.randf_range(900.0, 1200.0), 0.3, 70.0], [rng.randf_range(2300.0, 2700.0), 0.15, 90.0]], rng)
	return _finish(out, 0.14, 0.6)


## A chest lid: a short creak and the wooden thump of it coming to rest.
static func chest(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.6))
	var src := _buf(int(RATE * 0.25))
	var ph := 0.0
	var f := rng.randf_range(120.0, 170.0)
	for i in src.size():
		f = clampf(f + rng.randf_range(-4.0, 4.0), 90.0, 240.0)
		ph = fmod(ph + f / RATE, 1.0)
		src[i] = (ph * 2.0 - 1.0) * sin(PI * float(i) / src.size())
	_mix(out, _filter(src, "bp", 900.0, 3.0), 0.0, 0.8, 0.0)
	var g := rng.randf_range(170.0, 220.0)
	_modes(out, 0.24, [[g, 0.6, 20.0], [g * 2.2, 0.3, 30.0]], rng)
	_glide(out, 0.24, 0.12, 90.0, 60.0, 0.4, 25.0)
	return _finish(out, 0.12, 0.7)


# --- Water and fire ------------------------------------------------------------------------------------------------

## Something hitting water: the slap, bubbles glugging up, droplets falling back.
static func splash(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.9))
	_mix(out, _filter(_noise(int(RATE * 0.3), rng), "bp", rng.randf_range(900.0, 1300.0), 0.6), 0.0, 1.2, 12.0, 0.004)
	_mix(out, _filter(_noise(int(RATE * 0.3), rng), "lp", 400.0), 0.0, 0.8, 14.0, 0.004)
	for k in 9:
		_glide(out, rng.randf_range(0.03, 0.35), rng.randf_range(0.03, 0.06), rng.randf_range(300.0, 600.0), rng.randf_range(900.0, 1700.0), rng.randf_range(0.08, 0.2), 40.0)
	for k in 6:
		var at := rng.randf_range(0.25, 0.7)
		_glide(out, at, 0.04, rng.randf_range(1400.0, 2200.0), rng.randf_range(2400.0, 3200.0), 0.06, 60.0)
	return _finish(out, 0.1, 0.8)


## A swimming stroke: water pushed aside and a bubble or two.
static func stroke(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.5))
	var slosh := _filter(_noise(int(RATE * 0.4), rng), "bp", rng.randf_range(450.0, 650.0), 0.7)
	for i in slosh.size():
		slosh[i] *= sin(PI * float(i) / slosh.size())
	_mix(out, slosh, 0.0, 0.8, 1.5, 0.02)
	for k in 2:
		_glide(out, rng.randf_range(0.1, 0.3), 0.05, rng.randf_range(400.0, 600.0), rng.randf_range(900.0, 1300.0), 0.1, 45.0)
	return _finish(out, 0.06, 0.55)


## A water drop landing in a pool: a quick rising "plip" (a bubble forming) with a soft tail.
static func drip(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var out := _buf(int(RATE * 0.35))
	_glide(out, 0.0, 0.06, rng.randf_range(700.0, 1000.0), rng.randf_range(1600.0, 2400.0), 0.6, 35.0)
	_mix(out, _filter(_noise(int(RATE * 0.005), rng), "hp", 3000.0), 0.0, 0.2, 800.0)
	return _finish(out, 0.3, 0.5)


## A campfire, as a seamless loop: the soft roar of the flames, crackles and the odd snap of a log.
static func fire_loop(seconds := 6.0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var n := int(RATE * seconds)
	var out := _buf(n + RATE)
	var roar := _filter(_noise(out.size(), rng), "lp", 260.0)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = roar[i] * (0.5 + 0.2 * sin(t * 2.3) + 0.15 * sin(t * 5.1 + 1.0))
	_grains(out, rng, int(seconds * 14.0), 0.0, seconds + 0.9, 1500.0, 5000.0, 0.35, 0.0015)
	for k in int(seconds * 1.2):   # snaps
		var at := rng.randf_range(0.0, seconds + 0.8)
		_mix(out, _filter(_noise(int(RATE * 0.01), rng), "hp", 1200.0), at, rng.randf_range(0.4, 0.8), 250.0)
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	for i in out.size():
		out[i] *= 0.6 / maxf(top, 0.001)
	return to_stream(_make_loop(out, n, RATE), true)


## A river nearby, as a seamless loop: water babbling over stones.
static func river_loop(seconds := 6.0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 59
	var n := int(RATE * seconds)
	var out := _buf(n + RATE)
	var wash := _filter(_noise(out.size(), rng), "bp", 650.0, 0.6)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = wash[i] * (0.55 + 0.25 * sin(t * 1.7) * sin(t * 0.6 + 0.4))
	for k in int(seconds * 30.0):   # babbling: little bubbles
		_glide(out, rng.randf_range(0.0, seconds + 0.9), rng.randf_range(0.02, 0.05), rng.randf_range(350.0, 700.0), rng.randf_range(800.0, 1600.0), rng.randf_range(0.04, 0.12), 50.0)
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	for i in out.size():
		out[i] *= 0.6 / maxf(top, 0.001)
	return to_stream(_make_loop(out, n, RATE), true)


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
		"hiss":   # snakes: a breathy rasp
			var dur := rng.randf_range(0.5, 0.9)
			out = _buf(int(RATE * dur))
			var hp := 0.0
			var last := 0.0
			for i in out.size():
				var t := float(i) / RATE
				var n := rng.randf_range(-1, 1)
				hp = 0.6 * (hp + n - last)   # high-passed noise
				last = n
				out[i] = hp * minf(t / 0.05, 1.0) * (1.0 - t / dur) * 0.35
		"croak":  # frogs: a low ratcheting croak, two or three pulses
			var pulses := rng.randi_range(2, 3)
			var pulse := rng.randf_range(0.07, 0.1)
			var f := rng.randf_range(160.0, 260.0) / sqrt(maxf(size, 0.1) * 4.0)
			out = _buf(int(RATE * pulse * pulses * 1.3))
			for i in out.size():
				var t := float(i) / RATE
				var k := fmod(t, pulse * 1.3) / pulse
				if k < 1.0:
					var buzz := pow(maxf(sin(TAU * f * t), 0.0), 2.0) + 0.4 * sin(TAU * f * 3.0 * t)
					out[i] = buzz * sin(PI * k) * 0.4
		"squawk":   # parrots: a harsh rising-falling screech
			var dur := rng.randf_range(0.18, 0.3)
			var f := rng.randf_range(900.0, 1500.0)
			out = _buf(int(RATE * dur))
			var ph := 0.0
			for i in out.size():
				var t := float(i) / RATE
				ph += TAU * f * (1.0 + 0.5 * sin(PI * t / dur)) / RATE
				var harsh := sin(ph) + 0.6 * sin(ph * 2.0) + 0.4 * sin(ph * 3.01) + rng.randf_range(-0.2, 0.2)
				out[i] = harsh * sin(PI * t / dur) * 0.22
		"chatter":   # monkeys: quick high whoops
			var calls := rng.randi_range(3, 5)
			var each := 0.13
			var f0 := rng.randf_range(500.0, 800.0)
			out = _buf(int(RATE * each * calls))
			for i in out.size():
				var t := float(i) / RATE
				var k := fmod(t, each) / each
				var f := f0 * (1.0 + 0.8 * k)
				out[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * sin(PI * k) * 0.3
		"bark":   # foxes and coyotes: a sharp yip
			var dur := rng.randf_range(0.16, 0.26)
			var f := rng.randf_range(500.0, 800.0) / sqrt(size)
			out = _buf(int(RATE * dur))
			var ph := 0.0
			for i in out.size():
				var t := float(i) / RATE
				ph += TAU * f * (1.2 - 0.5 * t / dur) / RATE
				out[i] = (sin(ph) * 0.6 + sin(ph * 2.0) * 0.3 + rng.randf_range(-0.15, 0.15)) * sin(PI * t / dur) * 0.45
		"honk":   # penguins and seals: a brassy honk
			var dur := rng.randf_range(0.35, 0.6)
			var f := rng.randf_range(220.0, 380.0) / sqrt(size)
			out = _buf(int(RATE * dur))
			var ph := 0.0
			for i in out.size():
				var t := float(i) / RATE
				ph += TAU * f * (1.0 + 0.08 * sin(TAU * 7.0 * t)) / RATE
				var brass := sin(ph) + 0.7 * sin(ph * 2.0) + 0.5 * sin(ph * 3.0) + 0.3 * sin(ph * 4.0)
				out[i] = brass * sin(PI * minf(t / dur, 1.0)) * minf(t / 0.02, 1.0) * 0.25
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


## A distant rumble in the rock: low, slow-swelling noise.
static func rumble(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 2.6)
	var out := _buf(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * clampf(t / 2.6, 0.0, 1.0)) * (0.7 + 0.3 * sin(t * 9.0))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		out[i] = lp2 * env * 9.0
	return _finish(out, 0.0, 0.8)


## A bat's squeak: a tiny high chirp.
static func squeak(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.07)
	var out := _buf(n)
	var f0 := rng.randf_range(3200.0, 4200.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * f0 * (1.0 - t * 4.0) / RATE
		out[i] = sin(ph) * sin(PI * t / 0.07) * 0.22
	return to_stream(out)


## The hollow tone of a cave: a low drone with air moving through it (seamless loop).
static func cave_tone(seconds := 8.0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var rate := 16000
	var n := int(rate * seconds)
	var out := PackedFloat32Array()
	out.resize(n + rate)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.006
		var hum := sin(TAU * 55.0 * t) * 0.08 + sin(TAU * 82.4 * t + sin(t * 0.7)) * 0.05
		out[i] = lp * 6.0 * (0.7 + 0.3 * sin(TAU * t / seconds)) + hum
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
