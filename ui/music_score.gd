class_name MusicScore
extends RefCounted
## Original eight-bar D-minor electronic score, used by the offline rebuild tool.
## Shipping playback uses compressed Ogg files; no gameplay RNG is consumed.
const RATE := 22050
const MODES := ["menu", "map", "combat", "boss"]

static func render(mode: String) -> AudioStreamWAV:
	var intensity := MODES.find(mode)
	var bpm: float = [88.0, 100.0, 116.0, 128.0][clampi(intensity, 0, 3)]
	var beat := 60.0 / bpm
	var count := int(round(beat * 32.0 * RATE))
	beat = float(count) / RATE / 32.0
	var mix := PackedFloat32Array()
	mix.resize(count)
	# Dm9 – Bbmaj7 – Fmaj7 – Csus2, then a small melodic variation.
	var chords := [[50, 53, 57, 64], [46, 50, 53, 57], [48, 53, 57, 60], [48, 55, 58, 62]]
	var roots := [38, 34, 41, 36]
	var motif := [0, 2, 1, 3, 2, 1, 3, 2]
	for bar in 8:
		var chord: Array = chords[bar % 4]
		for note in chord:
			_note(mix, bar * 4 * beat, 4.5 * beat, int(note), 0.025, "pad")
		for step in 8:
			var start := (bar * 4 + step * 0.5) * beat
			if intensity >= 2 or step % 2 == 0:
				_note(mix, start, beat * 0.38, roots[bar % 4], 0.12 if intensity >= 2 else 0.08, "bass")
			if intensity >= 1 or step % 2 == 0:
				var index: int = motif[(step + (2 if bar >= 4 else 0)) % 8]
				var note: int = chord[index] + 12
				_note(mix, start, beat * 0.62, note, 0.04, "pluck")
				_note(mix, start + beat * 0.75, beat * 0.62, note, 0.012, "pluck")
			if intensity >= 1:
				_drum(mix, start, 0.07, "hat", 0.022 if step % 2 == 0 else 0.035, bar * 8 + step)
		for step in 4:
			var start := (bar * 4 + step) * beat
			if intensity >= 2 or (intensity == 1 and step % 2 == 0):
				_drum(mix, start, 0.22, "kick", 0.19, bar * 4 + step)
			if intensity >= 2 and step % 2 == 1:
				_drum(mix, start, 0.16, "snare", 0.085, bar * 4 + step)
		if intensity == 3:
			for step in [5, 11, 14]:
				_note(mix, (bar * 4 + step * 0.25) * beat, beat * 0.18, roots[bar % 4] + 12, 0.07, "bass")
			if bar % 2 == 1:
				_drum(mix, (bar * 4 + 3.75) * beat, 0.12, "snare", 0.045, bar)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(tanh(mix[i] * 1.3) * 24000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

static func _note(mix: PackedFloat32Array, start: float, duration: float, midi: int, gain: float, voice: String) -> void:
	var frequency := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var offset := int(start * RATE)
	var count := int(duration * RATE)
	for i in count:
		var t := float(i) / RATE
		var u := float(i) / count
		var phase := TAU * frequency * t
		var env := minf(t / 0.006, 1.0) * pow(1.0 - u, 2.0)
		var value := sin(phase)
		match voice:
			"pad":
				env = pow(sin(PI * u), 2.0)
				value = sin(phase) * 0.7 + sin(phase * 1.003) * 0.3
			"bass": value = sin(phase) * 0.8 + sin(phase * 2.0) * 0.15 + sin(phase * 3.0) * 0.05
			"pluck": value = sin(phase + sin(phase * 2.0) * exp(-t * 12.0))
		mix[(offset + i) % mix.size()] += value * env * gain

static func _drum(mix: PackedFloat32Array, start: float, duration: float, kind: String, gain: float, seed_value: int) -> void:
	var offset := int(start * RATE)
	var count := int(duration * RATE)
	var seed_state := seed_value + 92821
	var previous := 0.0
	for i in count:
		var t := float(i) / RATE
		var u := float(i) / count
		seed_state = (seed_state * 1664525 + 1013904223) & 0x7fffffff
		var noise := float(seed_state) / 1073741824.0 - 1.0
		var value := (noise - previous) * 0.5
		previous = noise
		if kind == "kick":
			value = sin(TAU * (48.0 * t + 7.0 * (1.0 - exp(-t * 24.0))))
		elif kind == "snare":
			value = value * 0.75 + sin(TAU * 180.0 * t) * 0.25
		var envelope := minf(t / 0.002, 1.0) * pow(1.0 - u, 3.0)
		mix[(offset + i) % mix.size()] += value * gain * envelope
