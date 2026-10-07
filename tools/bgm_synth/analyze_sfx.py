"""godot/scripts/sfx.gd 의 효과음을 그대로 재현해 레벨/대역을 측정하고 BGM 과 비교한다."""
import os
import sys

import numpy as np
from scipy.io import wavfile

RATE = 22050
rng = np.random.default_rng(1)


def make(dur, fn):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    v = np.clip(fn(t), -1, 1)
    i = np.arange(n)
    v *= np.minimum(1, i / 40) * np.minimum(1, (n - i) / 80)
    return v * 30000 / 32768


def rnd(t):
    return rng.uniform(-1, 1, len(t))


def chime(t):
    n = np.where(t < 0.1, 880.0, np.where(t < 0.2, 1108.7, 1318.5))
    return (np.sin(2*np.pi*n*t)*0.5 + np.sin(2*np.pi*n*2*t)*0.15) * np.exp(-np.fmod(t, 0.1)*6) * np.exp(-t*2.5)


def sad(t):
    n = np.where(t < 0.3, 392.0, np.where(t < 0.6, 349.2, 311.1))
    return np.sin(2*np.pi*n*t) * 0.4 * np.exp(-np.fmod(t, 0.3)*3)


SFX = {
    "pop": (0.14, lambda t: np.sin(2*np.pi*(520 + 900*np.exp(-t*30))*t) * np.exp(-t*28)),
    "thud": (0.16, lambda t: (np.sin(2*np.pi*(150*np.exp(-t*8) + 60)*t)*0.9 + rnd(t)*0.4*np.exp(-t*60)) * np.exp(-t*20)),
    "whoosh": (0.2, lambda t: rnd(t) * np.sin(np.pi*t/0.2) * 0.35),
    "boom": (0.5, lambda t: (np.sin(2*np.pi*(90*np.exp(-t*4) + 35)*t)*0.8 + rnd(t)*0.5*np.exp(-t*9)) * np.exp(-t*6)),
    "poof": (0.3, lambda t: rnd(t)*0.45*np.exp(-t*12) + np.sin(2*np.pi*(300 + 400*t)*t)*0.2*np.exp(-t*14)),
    "chime": (0.6, chime),
    "tick": (0.05, lambda t: np.sin(2*np.pi*1500*t)*np.exp(-t*90)*0.6),
    "clash": (0.7, lambda t: (np.sin(2*np.pi*(220 + 40*np.sin(t*30))*t)*0.4 + np.sin(2*np.pi*(220 + 40*np.sin(t*30))*1.5*t)*0.3 + rnd(t)*0.3*np.exp(-t*10)) * np.exp(-t*3.5)),
    "sad": (1.0, sad),
    "click": (0.06, lambda t: np.sin(2*np.pi*900*t)*np.exp(-t*60)*0.5),
}
# 게임 코드에서 쓰이는 대표 볼륨(dB)
TYPICAL_DB = {"pop": -6, "thud": -7, "whoosh": -14, "boom": -9, "poof": -5, "chime": -5,
              "tick": -8, "clash": -6, "sad": -4, "click": -6}


def db(x):
    return 20 * np.log10(max(x, 1e-9))


def centroid(x, sr):
    S = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    return float(np.sum(f * S) / np.sum(S))


def band_energy(x, sr, lo, hi):
    S = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / sr)
    return np.sum(S[(f >= lo) & (f < hi)]) / np.sum(S)


print(f"{'sfx':8s} {'peak@vol':>9s} {'rms50ms@vol':>12s} {'centroid':>9s}  low<200 / 200-2k / >2k")
peaks = []
for name, (dur, fn) in SFX.items():
    x = make(dur, fn) * 10 ** (TYPICAL_DB[name] / 20)
    w = min(len(x), int(0.05 * RATE))
    rms = np.sqrt(np.mean(x[:w] ** 2))
    peaks.append(rms)
    b = [band_energy(x, RATE, *r) for r in ((0, 200), (200, 2000), (2000, 11025))]
    print(f"{name:8s} {db(np.max(np.abs(x))):8.1f}  {db(rms):11.1f}  {centroid(x, RATE):8.0f}Hz  {b[0]:.2f} / {b[1]:.2f} / {b[2]:.2f}")
print(f"median SFX attack RMS (50 ms): {db(np.median(peaks)):.1f} dBFS")

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "trio_bgm_loop.wav")
sr, m = wavfile.read(path)
m = m.astype(np.float64).mean(axis=1) / 32768
win = int(0.4 * sr)
st = [np.sqrt(np.mean(m[i:i + win] ** 2)) for i in range(0, len(m) - win, win)]
print(f"BGM {os.path.basename(path)}: peak {db(np.max(np.abs(m))):.1f} dBFS, short-term RMS(400ms) median {db(np.median(st)):.1f} max {db(max(st)):.1f}")
b = [band_energy(m, sr, *r) for r in ((0, 200), (200, 2000), (2000, 24000))]
print(f"BGM band energy low<200 / 200-2k / >2k: {b[0]:.2f} / {b[1]:.2f} / {b[2]:.2f}")
