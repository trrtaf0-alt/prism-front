"""Render the original Prism Front loops. Requires numpy, scipy, and soundfile."""
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt
import soundfile as sf


RATE = 44100
TAU = 2 * np.pi
MUSIC = Path(__file__).resolve().parents[1] / "assets" / "music"

# MIDI voicings. The battle score quotes the D-F-A motif in a darker progression.
PATROL = [
    (38, (50, 57, 65, 76)), (34, (53, 57, 62, 72)),
    (41, (53, 60, 64, 69)), (36, (52, 55, 62, 67)),
    (38, (50, 57, 65, 76)), (34, (53, 57, 62, 72)),
    (43, (55, 58, 62, 69)), (33, (52, 55, 61, 70)),
]
FINALE = [
    (38, (50, 57, 65, 69)), (38, (50, 57, 65, 69)),
    (39, (51, 58, 62, 70)), (36, (48, 55, 63, 67)),
    (38, (50, 57, 65, 69)), (34, (46, 53, 62, 65)),
    (35, (47, 53, 59, 68)), (33, (45, 52, 61, 70)),
]
PATROL_LEAD = [
    [(0.75, 74), (1.5, 77), (2.5, 81)],
    [(0.0, 79), (2.75, 77)], [(0.5, 76), (1.5, 72), (3.0, 69)],
    [(1.0, 74), (2.75, 79)], [(0.75, 74), (1.5, 77), (2.5, 84)],
    [(0.0, 81), (1.5, 77), (3.0, 74)], [(0.5, 79), (2.0, 77)],
    [(0.75, 73), (2.5, 70)],
]
FINALE_LEAD = [
    [(0.0, 62), (1.5, 65), (2.5, 69)], [(0.5, 67), (1.5, 65), (3.0, 62)],
    [(0.0, 63), (2.0, 70), (3.0, 67)], [(0.0, 63), (2.5, 60)],
    [(0.0, 62), (1.5, 65), (2.5, 74)], [(0.0, 70), (1.5, 65), (3.0, 62)],
    [(0.0, 65), (1.5, 68), (2.5, 71)], [(0.0, 70), (2.0, 73)],
]


def timeline(seconds):
    return np.arange(round(seconds * RATE), dtype=np.float32) / RATE


def envelope(t, attack, release):
    return np.minimum(t / attack, 1) * np.minimum((len(t) / RATE - t) / release, 1)


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def pad(note, length, bright):
    t = timeline(length)
    p = TAU * hz(note) * t
    vibrato = 0.11 * np.sin(TAU * 0.28 * t + note)
    body = 0.48 * np.sin(p + vibrato) + 0.22 * np.sin(2 * p) + 0.12 * np.sin(3 * p + vibrato)
    sheen = 0.16 * np.sin(p * 1.003 + 0.18 * np.sin(2 * p))
    if bright:
        sheen += 0.15 * np.sin(4 * p + 0.55 * np.sin(p))
    return (body + sheen) * envelope(t, min(0.58, length * 0.27), 0.90)


def pluck(note, length, hard=False):
    t = timeline(length)
    p = TAU * hz(note) * t
    upper = np.sin(2.001 * p + 0.55 * np.sin(3.005 * p) * np.exp(-5 * t))
    body = np.sin(p + (2.1 if hard else 0.8) * np.exp(-3.2 * t) * np.sin(2 * p))
    return (0.68 * body + 0.3 * upper * np.exp(-4 * t)) * np.exp(-(2.6 if hard else 3.4) * t) * envelope(t, 0.016, 0.08)


def bass(note, length, hard):
    t = timeline(length)
    p = TAU * hz(note) * t
    body = 0.68 * np.sin(p) + 0.22 * np.sin(2 * p)
    grit = np.sin(3.001 * p + 1.2 * np.sin(p)) * np.exp(-5.0 * t)
    return (body + grit * (0.36 if hard else 0.1)) * envelope(t, 0.012, 0.07)


def drum(kind, rng, heavy):
    if kind == "kick":
        t = timeline(0.48 if heavy else 0.35)
        p = TAU * (43 * t + 68 * (1 - np.exp(-34 * t)) / 34)
        return np.sin(p) * np.exp(-10.5 * t) * envelope(t, 0.003, 0.075)
    if kind == "impact":
        t = timeline(0.84)
        noise = sosfilt(butter(2, (150, 3400), btype="bandpass", fs=RATE, output="sos"), rng.normal(size=len(t)))
        shell = np.sin(TAU * (105 * t + 0.75 * (1 - np.exp(-16 * t)))) * np.exp(-8.5 * t)
        return (0.68 * shell + 0.6 * noise * np.exp(-11 * t)) * envelope(t, 0.008, 0.21)
    t = timeline(0.125)
    noise = sosfilt(butter(2, (5700, 11000), btype="bandpass", fs=RATE, output="sos"), rng.normal(size=len(t)))
    return noise * np.exp(-34 * t) * envelope(t, 0.006, 0.03)


def render(heavy):
    tempo, bars = (132, 32) if heavy else (96, 24)
    beat_seconds = 60 / tempo
    mix = np.zeros((round(bars * 4 * beat_seconds * RATE), 2), dtype=np.float32)
    ambience = np.zeros_like(mix)
    rng = np.random.default_rng(271 if heavy else 461)

    def add(beat, mono, gain, pan=0, space=0):
        start = round(beat * beat_seconds * RATE) % len(mix)
        stereo = mono[:, None] * (gain * np.sqrt([(1 - pan) / 2, (1 + pan) / 2]))
        before_wrap = min(len(stereo), len(mix) - start)
        mix[start:start + before_wrap] += stereo[:before_wrap]
        mix[:len(stereo) - before_wrap] += stereo[before_wrap:]
        if space:
            ambience[start:start + before_wrap] += stereo[:before_wrap] * space
            ambience[:len(stereo) - before_wrap] += stereo[before_wrap:] * space

    harmony, melody = (FINALE, FINALE_LEAD) if heavy else (PATROL, PATROL_LEAD)
    for bar in range(bars):
        beat = bar * 4
        phrase = bar % 8
        section = bar // 8
        root, chord = harmony[phrase]
        for i, note in enumerate(chord):
            add(beat - 0.28 + 0.04*i, pad(note, beat_seconds * 5.35, heavy),
                0.055 if heavy else 0.085, (-0.70, 0.59, -0.36, 0.77)[i], 0.37)
        if heavy:
            bassline = [(0, root, 0.73), (1, root, 0.38), (1.75, root, 0.48),
                        (2.5, root, 0.48), (3.25, root + (12 if phrase % 2 else 7), 0.46)]
            if section == 2:
                bassline = bassline[:3] + [(3.25, root, 0.52)]
            kicks = (0, 1.75, 2.5, 3.25) if section in (1, 3) else (0, 2.5)
        else:
            bassline = [(0, root, 1.18), (1.5, root + 12, 0.41), (2.5, root, 0.89)]
            kicks = (0, 2.25) if section else (0,)
        for offset, note, duration in bassline:
            add(beat + offset, bass(note, duration * beat_seconds, heavy), 0.25 if heavy else 0.19)
        for offset in kicks:
            add(beat + offset, drum("kick", rng, heavy), 0.37 if heavy else 0.17)
        if heavy:
            add(beat + 2, drum("impact", rng, True), 0.32, 0.13, 0.18)
            if phrase in (0, 4):
                add(beat, drum("impact", rng, True), 0.25, -0.18, 0.42)
        if section or heavy:
            for step in range(1, 8, 2):
                add(beat + step / 2, drum("hat", rng, heavy), 0.076 if heavy else 0.044,
                    0.28 if step % 4 == 1 else -0.31, 0.10)
        if heavy or section:
            for step in range(8):
                if (step + phrase) % 4 == 3:
                    continue
                note = chord[(step + phrase) % len(chord)] + (12 if heavy and section == 3 else 0)
                add(beat + 0.5 * step, pluck(note, 0.49, heavy), 0.055 if heavy else 0.049,
                    -0.34 if step % 2 else 0.31, 0.45)
        for i, (offset, note) in enumerate(melody[phrase]):
            if not heavy and section == 0 and i != 1:
                continue
            if heavy and section == 2:
                note -= 12
            add(beat + offset, pluck(note, 1.25 if heavy else 1.75, heavy),
                (0.165 if heavy else 0.132) * (0.83 if i == 1 else 1), 0.06, 0.67)

    # Cross-channel echoes and tails wrap to the same transport grid as the score.
    for beats, gain in [(0.75, 0.27), (1.5, 0.16), (2.25, 0.08), (3.18, 0.042)]:
        offset = round(beats * beat_seconds * RATE)
        for channel in range(2):
            mix[offset:, channel] += ambience[:-offset, 1 - channel] * gain
            mix[:offset, channel] += ambience[-offset:, 1 - channel] * gain
    del ambience
    mix -= np.mean(mix, axis=0)
    mix *= 1.74 if heavy else 2.02
    np.tanh(mix, out=mix)
    mix *= (0.82 if heavy else 0.75) / np.max(np.abs(mix))
    # Smooth the codec boundary while keeping rhythmic and echo tails in time.
    edge = np.sin(np.linspace(0, np.pi / 2, round(0.006 * RATE), dtype=np.float32)) ** 2
    mix[:len(edge)] *= edge[:, None]
    mix[-len(edge):] *= edge[::-1, None]
    MUSIC.mkdir(parents=True, exist_ok=True)
    path = MUSIC / ("core_eclipse.ogg" if heavy else "neon_watch.ogg")
    with sf.SoundFile(path, "w", RATE, 2, format="OGG", subtype="VORBIS") as output:
        for start in range(0, len(mix), RATE):
            output.write(mix[start:start + RATE])
    print(f"{path.name}: {len(mix) / RATE:.2f} s, peak {np.max(np.abs(mix)):.3f}, RMS {np.sqrt(np.mean(mix**2)):.3f}")


if __name__ == "__main__":
    render(False)
    render(True)
