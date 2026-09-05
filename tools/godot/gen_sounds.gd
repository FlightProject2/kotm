extends SceneTree
## Synthesises placeholder sound effects into assets/generated/sfx/*.wav (headless).
## Shapes follow docs/game-plan/14-audio-vfx.md: noise bursts with filtered tails for shots,
## clanks for armor, a crack + ring for helmet pops, a two-tone sting for kills.

const RATE := 44100
const OUT := "res://assets/generated/sfx/"

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	_save("shot_rifle", _shot(rng, 0.32, 0.55, 140.0, 0.09))
	_save("shot_rifle_heavy", _shot(rng, 0.38, 0.45, 110.0, 0.11))
	_save("shot_sniper", _shot(rng, 0.6, 0.35, 90.0, 0.16))
	_save("shot_shotgun", _shot(rng, 0.45, 0.4, 100.0, 0.14))
	_save("shot_smg", _shot(rng, 0.18, 0.7, 180.0, 0.06))
	_save("shot_pistol", _shot(rng, 0.22, 0.75, 220.0, 0.05))
	_save("shot_distant", _shot(rng, 0.7, 0.12, 60.0, 0.25))
	_save("hit_flesh", _thud(rng, 0.12, 320.0))
	_save("hit_armor", _clank(0.16, 1800.0, 900.0))
	_save("armor_break", _clank(0.3, 1400.0, 500.0))
	_save("helmet_pop", _helmet(rng))
	_save("kill", _sting([880.0, 1320.0], 0.1, 0.3))
	_save("headshot", _sting([1320.0, 1760.0], 0.08, 0.25))
	_save("pickup", _blip(600.0, 900.0, 0.13))
	_save("reload", _clank(0.12, 700.0, 400.0))
	_save("crack", _crack(rng))
	_save("footstep", _thud(rng, 0.07, 180.0))
	_save("landing", _thud(rng, 0.2, 120.0))
	_save("ui_click", _blip(500.0, 500.0, 0.05))
	_save("zone_warning", _sting([440.0, 440.0, 660.0], 0.18, 0.35))
	print("SFX: written")
	quit(0)

func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)

func _lowpass(samples: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / RATE
	var a := dt / (rc + dt)
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var y := 0.0
	for i in samples.size():
		y += a * (samples[i] - y)
		out[i] = y
	return out

func _shot(rng: RandomNumberGenerator, length: float, lowpass_k: float, thump_hz: float, decay: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var t := float(i) / RATE
		raw[i] = rng.randf_range(-1, 1) * _env(t, 0.002, decay)
	var filtered := _lowpass(raw, 2500.0 * lowpass_k + 500.0)
	for i in n:
		var t := float(i) / RATE
		var thump := sin(TAU * thump_hz * t * maxf(0.2, 1.0 - t * 6.0)) * _env(t, 0.001, 0.05) * 0.8
		filtered[i] = clampf(filtered[i] * 1.6 + thump, -1.0, 1.0)
	return filtered

func _thud(rng: RandomNumberGenerator, length: float, hz: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * hz * t) * 0.6 + rng.randf_range(-0.3, 0.3)) * _env(t, 0.003, length * 0.35)
	return _lowpass(out, 900.0)

func _clank(length: float, hz1: float, hz2: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(hz1, hz2, minf(1.0, t / length))
		out[i] = (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.01 * t)) * 0.5 * _env(t, 0.002, length * 0.4)
	return out

func _helmet(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var crack := rng.randf_range(-1, 1) * _env(t, 0.001, 0.02)
		var ring := sin(TAU * 2600.0 * t) * 0.35 * _env(maxf(0.0, t - 0.02), 0.005, 0.18)
		out[i] = clampf(crack + ring, -1, 1)
	return out

func _sting(freqs: Array, step: float, decay: float) -> PackedFloat32Array:
	var n := int(RATE * (step * freqs.size() + decay))
	var out := PackedFloat32Array()
	out.resize(n)
	for k in freqs.size():
		var start := step * k
		for i in n:
			var t := float(i) / RATE - start
			if t < 0.0:
				continue
			var s := (0.6 * sin(TAU * float(freqs[k]) * t) + 0.25 * sin(TAU * float(freqs[k]) * 2.0 * t)) * _env(t, 0.01, decay) * 0.5
			out[i] = clampf(out[i] + s, -1, 1)
	return out

func _blip(f0: float, f1: float, length: float) -> PackedFloat32Array:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / length)
		phase += TAU * f / RATE
		out[i] = sin(phase) * 0.4 * _env(t, 0.005, length * 0.5)
	return out

func _crack(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = rng.randf_range(-1, 1) * _env(t, 0.0005, 0.012) * 0.8
	return out

func _save(name: String, samples: PackedFloat32Array) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	var err := wav.save_to_wav(OUT + name + ".wav")
	print("  %s.wav %s (%.2fs)" % [name, error_string(err), float(samples.size()) / RATE])
