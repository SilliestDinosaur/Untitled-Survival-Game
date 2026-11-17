class_name Instruments
extends RefCounted
## Synthesized instrument samples for the procedural music. Each instrument is rendered once at a
## base pitch and transposed with pitch_scale when played. Rendering uses single-cycle wavetables
## (cheap phase lookups) so the whole set builds in a fraction of a second on a worker thread.

const RATE := 24000
const TABLE := 2048
const BASE_MIDI := 60          ## melodic instruments are rendered at middle C
const BASS_MIDI := 36          ## bass instruments two octaves lower

## name -> {stream, base_midi}
static func build(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {}
	# Each world gets slightly different timbres (like the palette, the band changes per world).
	var warm := rng.randf_range(0.0, 1.0)
	out.pad = {"stream": _pad(_table_soft_saw(6 + int(warm * 4)), 5.0, 1.4, rng), "base": BASE_MIDI}
	out.dark_pad = {"stream": _pad(_table_hollow(), 6.0, 2.2, rng), "base": BASE_MIDI - 12}
	out.pluck = {"stream": _pluck(1.8, rng.randf_range(4.8, 5.6)), "base": BASE_MIDI}
	out.bell = {"stream": _bell(3.2), "base": BASE_MIDI + 12}
	out.flute = {"stream": _flute(1.6, rng), "base": BASE_MIDI + 12}
	out.bass = {"stream": _bass(1.4), "base": BASS_MIDI}
	out.strings = {"stream": _strings(2.2, rng), "base": BASE_MIDI}
	out.kick = {"stream": _kick(), "base": BASE_MIDI}
	out.tom = {"stream": _tom(), "base": BASE_MIDI}
	out.shaker = {"stream": _shaker(rng), "base": BASE_MIDI}
	out.rim = {"stream": _rim(rng), "base": BASE_MIDI}
	return out


# --- Wavetables -------------------------------------------------------------------

static func _additive(amps: Array) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TABLE)
	var peak := 0.0
	for i in TABLE:
		var ph := TAU * float(i) / TABLE
		var s := 0.0
		for h in amps.size():
			s += amps[h] * sin(ph * (h + 1))
		t[i] = s
		peak = maxf(peak, absf(s))
	for i in TABLE:
		t[i] /= peak
	return t


static func _table_soft_saw(harmonics: int) -> PackedFloat32Array:
	var amps := []
	for h in harmonics:
		amps.append(1.0 / pow(h + 1, 1.35))
	return _additive(amps)


static func _table_hollow() -> PackedFloat32Array:
	# Odd harmonics only: a soft clarinet / square-ish drone.
	return _additive([1.0, 0.0, 0.3, 0.0, 0.12, 0.0, 0.05])


static func _read(table: PackedFloat32Array, phase: float) -> float:
	var p := phase * TABLE
	var i := int(p) % TABLE
	var f := p - floorf(p)
	return lerpf(table[i], table[(i + 1) % TABLE], f)


# --- Instruments -------------------------------------------------------------------

static func _freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## Slow-swelling detuned chorus pad.
static func _pad(table: PackedFloat32Array, dur: float, attack: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := _freq(BASE_MIDI)
	var detune := [1.0, 1.0035 + rng.randf() * 0.002, 0.9968 - rng.randf() * 0.002, 2.001]
	var gains := [0.45, 0.32, 0.32, 0.08]
	var phases := [0.0, 0.31, 0.67, 0.12]
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for v in 4:
			phases[v] = fmod(phases[v] + f * detune[v] / RATE, 1.0)
			s += _read(table, phases[v]) * gains[v]
		# A gentle low-pass that opens with the swell.
		var env := smoothstep(0.0, attack, t) * (1.0 - smoothstep(dur - 1.6, dur, t))
		lp += (s - lp) * (0.12 + 0.25 * env)
		out[i] = lp * env * 0.55
	return SoundGen.to_stream(out, false, RATE)


## Kalimba-like pluck: fundamental plus an inharmonic tine partial.
static func _pluck(dur: float, tine: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := _freq(BASE_MIDI)
	for i in n:
		var t := float(i) / RATE
		var a := minf(t / 0.003, 1.0)
		var s := sin(TAU * f * t) * exp(-t * 2.6)
		s += sin(TAU * f * 2.0 * t) * 0.18 * exp(-t * 5.0)
		s += sin(TAU * f * tine * t) * 0.22 * exp(-t * 14.0)
		out[i] = s * a * 0.5
	return SoundGen.to_stream(out, false, RATE)


## Glassy bell with inharmonic partials.
static func _bell(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := _freq(BASE_MIDI + 12)
	var parts := [[1.0, 1.0, 1.4], [2.76, 0.4, 2.6], [5.4, 0.22, 4.5], [8.93, 0.1, 7.0], [0.5, 0.2, 1.1]]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p: Array in parts:
			s += sin(TAU * f * p[0] * t) * p[1] * exp(-t * p[2])
		out[i] = s * minf(t / 0.002, 1.0) * 0.32
	return SoundGen.to_stream(out, false, RATE)


## Breathy flute / ocarina with delayed vibrato.
static func _flute(dur: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := _freq(BASE_MIDI + 12)
	var ph := 0.0
	var noise_lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var vib := 1.0 + 0.006 * sin(TAU * 5.2 * t) * smoothstep(0.25, 0.6, t)
		ph = fmod(ph + f * vib / RATE, 1.0)
		var s := sin(TAU * ph) + 0.12 * sin(TAU * ph * 2.0) + 0.05 * sin(TAU * ph * 3.0)
		noise_lp += (rng.randf_range(-1.0, 1.0) - noise_lp) * 0.25
		var env := smoothstep(0.0, 0.07, t) * (1.0 - smoothstep(dur - 0.5, dur, t))
		out[i] = (s * 0.42 + noise_lp * 0.06 * (0.4 + env)) * env
	return SoundGen.to_stream(out, false, RATE)


## Round sub bass.
static func _bass(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f := _freq(BASS_MIDI)
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.02, t) * exp(-t * 1.2) * (1.0 - smoothstep(dur - 0.3, dur, t))
		var s := sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t) + 0.08 * sin(TAU * f * 3.0 * t)
		out[i] = s * env * 0.6
	return SoundGen.to_stream(out, false, RATE)


## Tremolo string section for tense moments.
static func _strings(dur: float, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var table := _table_soft_saw(10)
	var f := _freq(BASE_MIDI)
	var phases := [0.0, 0.4, 0.8]
	var det := [1.0, 1.004, 0.995]
	var lp := 0.0
	var trem_rate := rng.randf_range(7.0, 9.0)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for v in 3:
			phases[v] = fmod(phases[v] + f * det[v] / RATE, 1.0)
			s += _read(table, phases[v])
		lp += (s - lp) * 0.3
		var env := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(dur - 0.6, dur, t))
		var trem := 0.7 + 0.3 * sin(TAU * trem_rate * t)
		out[i] = lp * env * trem * 0.2
	return SoundGen.to_stream(out, false, RATE)


static func _kick() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 48.0 + 70.0 * exp(-t * 30.0)
		ph += f / RATE
		out[i] = sin(TAU * ph) * exp(-t * 7.0) * minf(t / 0.002, 1.0) * 0.8
	return SoundGen.to_stream(out, false, RATE)


static func _tom() -> AudioStreamWAV:
	var n := int(0.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 95.0 + 45.0 * exp(-t * 18.0)
		ph += f / RATE
		out[i] = (sin(TAU * ph) + 0.3 * sin(TAU * ph * 1.6)) * exp(-t * 6.5) * minf(t / 0.002, 1.0) * 0.55
	return SoundGen.to_stream(out, false, RATE)


static func _shaker(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.12 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev   # crude high-pass
		prev = w
		out[i] = hp * smoothstep(0.0, 0.02, t) * exp(-t * 35.0) * 0.25
	return SoundGen.to_stream(out, false, RATE)


static func _rim(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(0.15 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * 820.0 * t) * 0.5 + sin(TAU * 1370.0 * t) * 0.3 + rng.randf_range(-1.0, 1.0) * 0.3
		out[i] = s * exp(-t * 45.0) * 0.3
	return SoundGen.to_stream(out, false, RATE)
