"""Original score for the Gixbee film. Sparse piano, a wide pad, and a long hall."""

import numpy as np

SR = 44100
DUR = 36.0


def midi_to_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def piano(freq, n, vel):
    t = np.arange(n, dtype=np.float64) / SR
    sig = np.zeros(n, dtype=np.float64)
    for k in range(1, 18):
        stretch = 1.0 + 0.00015 * k * k
        amp = vel * (0.55 ** (k - 1))
        partial = np.exp(-t * (0.42 + 0.38 * (k - 1)))
        sig += amp * partial * np.sin(2.0 * np.pi * freq * k * stretch * t)
    attack = int(0.004 * SR)
    sig[:attack] *= np.linspace(0.0, 1.0, attack)
    sig *= np.exp(-t / 3.4)
    hammer = np.random.default_rng(int(freq * 10)).standard_normal(min(n, int(0.02 * SR)))
    hammer *= np.exp(-np.arange(len(hammer)) / (0.004 * SR)) * vel * 0.04
    sig[: len(hammer)] += hammer
    return sig


def pad(freqs, n, vel):
    t = np.arange(n, dtype=np.float64) / SR
    sig = np.zeros(n, dtype=np.float64)
    for f in freqs:
        for detune in (-0.35, 0.0, 0.35):
            hz = f * (2.0 ** (detune / 1200.0))
            sig += np.sin(2.0 * np.pi * hz * t)
            sig += 0.35 * np.sin(2.0 * np.pi * hz * 2.0 * t)
    attack = int(1.05 * SR)
    release = int(1.4 * SR)
    env = np.ones(n)
    env[:attack] = np.linspace(0.0, 1.0, attack) ** 2
    if release < n:
        env[-release:] *= np.linspace(1.0, 0.0, release)
    sig *= env
    sig *= vel / (3.0 * max(len(freqs), 1))
    return sig


def place(stereo, mono, start, pan):
    i0 = int(start * SR)
    i1 = min(len(stereo[0]), i0 + len(mono))
    if i1 <= i0:
        return
    chunk = mono[: i1 - i0]
    left = np.sqrt(0.5 * (1.0 - pan))
    right = np.sqrt(0.5 * (1.0 + pan))
    stereo[0, i0:i1] += chunk * left
    stereo[1, i0:i1] += chunk * right


def lowpass(x, cutoff):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= 1.0 / (1.0 + (freqs / cutoff) ** 3)
    return np.fft.irfft(spec, len(x))


def hall(x):
    rng = np.random.default_rng(7)
    ir_n = int(2.6 * SR)
    ir = rng.standard_normal(ir_n) * np.exp(-np.linspace(0.0, 7.2, ir_n))
    ir = lowpass(ir, 3200)
    ir[0] = 0.0
    ir /= np.max(np.abs(ir)) + 1e-9
    nfft = 1 << (len(x) + len(ir) - 2).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[: len(x)]
    wet = lowpass(wet, 5000)
    return x + wet * 0.42


def render():
    n = int(DUR * SR)
    stereo = np.zeros((2, n), dtype=np.float64)

    # time, midi, duration, velocity, pan
    notes = [
        # Logo. A low D, almost alone.
        (0.45, 38, 5.0, 0.20, 0.0),
        (0.70, 50, 4.2, 0.08, -0.2),
        # The Skill / Intelligence / Network.
        (4.35, 62, 2.6, 0.22, -0.08),
        (4.85, 65, 2.6, 0.24, 0.06),
        (5.35, 69, 3.4, 0.26, 0.0),
        (6.20, 74, 3.6, 0.16, 0.10),
        (6.20, 50, 4.0, 0.07, -0.15),
        (6.20, 57, 4.0, 0.06, 0.18),
        # Software for local services and work.
        (10.45, 46, 4.8, 0.18, 0.0),
        (10.55, 58, 4.4, 0.10, -0.16),
        (10.65, 62, 4.2, 0.09, 0.08),
        (10.75, 65, 4.0, 0.08, 0.18),
        (11.20, 72, 2.6, 0.15, 0.0),
        (12.55, 69, 2.3, 0.13, -0.06),
        (13.70, 65, 2.2, 0.11, 0.08),
        # Four ways.
        (15.10, 41, 5.4, 0.17, 0.0),
        (15.22, 53, 5.0, 0.09, -0.14),
        (15.34, 57, 4.8, 0.08, 0.06),
        (15.46, 60, 4.6, 0.08, 0.16),
        (16.30, 69, 2.8, 0.12, 0.0),
        (18.10, 65, 2.4, 0.10, -0.08),
        # Someone accepts.
        (20.90, 48, 4.8, 0.17, 0.0),
        (21.02, 52, 4.4, 0.10, -0.12),
        (21.14, 55, 4.2, 0.09, 0.12),
        (21.20, 64, 2.2, 0.16, 0.0),
        (22.45, 67, 2.2, 0.15, 0.06),
        (23.55, 69, 2.6, 0.17, -0.04),
        # Hosted on Microsoft Azure.
        (25.45, 45, 4.6, 0.15, 0.0),
        (25.55, 57, 4.3, 0.09, -0.16),
        (25.68, 64, 4.0, 0.08, 0.14),
        (26.25, 69, 3.4, 0.13, 0.0),
        (27.80, 72, 2.4, 0.11, 0.08),
        # March 2027. The chord lifts.
        (30.10, 38, 5.6, 0.24, 0.0),
        (30.20, 50, 5.4, 0.13, -0.14),
        (30.32, 54, 5.2, 0.12, 0.08),
        (30.44, 57, 5.0, 0.11, 0.18),
        (30.60, 66, 3.6, 0.18, 0.0),
        (31.45, 69, 3.2, 0.16, 0.06),
        (32.20, 74, 3.5, 0.20, 0.0),
    ]

    for start, note, dur, vel, pan in notes:
        samples = int((dur + 1.2) * SR)
        tone = piano(midi_to_hz(note), samples, vel)
        place(stereo, tone, start, pan)

    pads = [
        (0.3, 8.8, (midi_to_hz(38), midi_to_hz(50), midi_to_hz(57)), 0.05),
        (10.2, 5.2, (midi_to_hz(46), midi_to_hz(58), midi_to_hz(65)), 0.055),
        (15.0, 5.6, (midi_to_hz(41), midi_to_hz(53), midi_to_hz(60)), 0.05),
        (20.7, 4.8, (midi_to_hz(48), midi_to_hz(52), midi_to_hz(55)), 0.05),
        (25.3, 4.8, (midi_to_hz(45), midi_to_hz(57), midi_to_hz(64)), 0.045),
        (29.9, 6.0, (midi_to_hz(38), midi_to_hz(54), midi_to_hz(57)), 0.06),
    ]
    for start, dur, freqs, vel in pads:
        samples = int(dur * SR)
        place(stereo, pad(freqs, samples, vel), start, -0.55)
        place(stereo, pad(freqs, samples, vel), start, 0.55)

    left = hall(lowpass(stereo[0], 9000))
    right = hall(lowpass(stereo[1], 9000))
    fade_in = int(0.45 * SR)
    fade_out = int(2.2 * SR)
    env = np.ones(n)
    env[:fade_in] = np.linspace(0.0, 1.0, fade_in)
    env[-fade_out:] *= np.linspace(1.0, 0.0, fade_out) ** 1.4
    left *= env
    right *= env
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)), 1e-9)
    left *= 0.89 / peak
    right *= 0.89 / peak
    return np.column_stack([left, right])


def write_wav(path, audio):
    pcm = np.clip(audio, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype(np.int16)
    import wave
    with wave.open(path, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())


if __name__ == "__main__":
    audio = render()
    write_wav("/tmp/gixbee-score.wav", audio)
    window = int(2 * SR)
    mono = audio.mean(axis=1)
    print("peak", float(np.max(np.abs(audio))))
    for i in range(0, len(mono), window):
        chunk = mono[i : i + window]
        rms = float(np.sqrt(np.mean(chunk ** 2)))
        print(f"{i / SR:4.0f}s  rms {rms:.4f}")
