"""
Trio Chess BGM #3 "필드" - numpy/scipy 로만 합성하는 걷는 느낌의 필드 루프.

- 48 kHz / 90 BPM / 4/4 / 16 마디 (16분음표 = 정확히 8,000 샘플, 루프 42.667 초)
- D 장조. 플루트 멜로디 + 마림바 8분 오스티나토 + 피치카토 베이스 + 부드러운 킥/림/셰이커.
  후반 8마디는 일렉트릭 피아노 뒷박 컴핑이 더해진다.
- 원형 렌더링/이펙트는 synth_bgm.py, 일부 악기는 synth_bgm_calm.py 것을 재사용.
- 출력: out/trio_bgm_field_loop.wav (smpl 루프 청크), out/trio_bgm_field_preview_x2.wav
- --game: 행군 모드용 믹스 out/trio_bgm_field_game.wav 를 만들고 godot/audio/bgm_field.wav 로 복사.
  전투 효과음 자리를 비운다: 플루트 -1.4 dB, 45 Hz 하이패스, 90 Hz -4 dB(thud/boom), 1.5 kHz -2.5 dB(pop/chime).

실행:  python synth_bgm_field.py          (감상용)
       python synth_bgm_field.py --game   (게임용)
"""
import os
import shutil
import sys

import numpy as np
from scipy import signal

from synth_bgm import (SR, OUT_DIR, peaking_sos, add_wrapped, pan, adsr, circular_filter, circular_delay,
                       circular_convolve, write_wav_with_loop, mtof, nmidi)
from synth_bgm_calm import epiano, soft_pad, shaker, voice_range, make_hall_ir

BPM = 90
STEP = SR * 60 // BPM // 4          # 8,000 샘플
assert STEP * BPM * 4 == SR * 60
BARS = 16
L = STEP * 16 * BARS
rng = np.random.default_rng(90)

# ---------------------------------------------------------------- 악보

D, Bm, G, A, Fsm, Em, Asus = ((2, [2, 6, 9]), (11, [11, 14, 18]), (7, [7, 11, 14]), (9, [9, 13, 16]),
                              (6, [6, 9, 13]), (4, [4, 7, 11]), (9, [9, 14, 16]))
CHORDS = [D, Bm, G, A, D, Fsm, G, A,
          G, A, Fsm, Bm, Em, A, G, Asus]      # Asus4 -> 루프 처음 D 로 해결

MELODY = [
    "A5:3 F#5:1 A5:4 D6:4 A5:4",
    "B5:6 A5:2 F#5:4 D5:4",
    "G5:3 A5:1 B5:4 D6:4 B5:4",
    "C#6:6 B5:2 A5:8",
    "A5:3 F#5:1 A5:4 D6:4 E6:4",
    "F#6:6 E6:2 C#6:4 A5:4",
    "B5:4 D6:2 B5:2 G5:4 B5:4",
    "A5:12 -:4",
    "D6:4 B5:2 D6:2 G6:6 F#6:2",
    "E6:4 C#6:4 A5:8",
    "C#6:4 A5:2 C#6:2 F#6:4 E6:4",
    "D6:6 C#6:2 B5:8",
    "G5:4 B5:2 E6:2 D6:4 B5:4",
    "C#6:4 E6:4 A5:4 C#6:4",
    "B5:4 D6:2 B5:2 G5:2 A5:2 B5:4",
    "A5:8 G5:2 F#5:2 E5:4",           # E5 -> 루프 첫 음 A5
]


def parse_melody():
    notes = []
    for bar, line in enumerate(MELODY):
        pos = 0
        for tok in line.split():
            name, ln = tok.split(":")
            ln = int(ln)
            if name != "-":
                notes.append((bar * 16 + pos, ln, nmidi(name)))
            pos += ln
        assert pos == 16, f"bar {bar + 1} has {pos} steps"
    return notes


# ---------------------------------------------------------------- 악기

SOS_BREATH = signal.butter(2, [1800, 5000], btype="bandpass", fs=SR, output="sos")


def flute(f, gate):
    r = int(0.09 * SR)
    n = gate + r
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.18) / 0.25, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    tone = np.sin(ph) + 0.32 * np.sin(2 * ph) + 0.10 * np.sin(3 * ph) + 0.04 * np.sin(4 * ph)
    breath = signal.sosfilt(SOS_BREATH, rng.standard_normal(n)) * 0.12 * (0.4 + 0.6 * np.exp(-t * 8))
    env = adsr(n, 0.045 * SR, 0.25 * SR, 0.8, r, gate)
    return (tone + breath) * env


def marimba(f):
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    sig = (np.sin(2 * np.pi * f * t) * np.exp(-t * 5.5)
           + 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t * 22)
           + 0.08 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t * 60))
    env = np.minimum(1, t / 0.0015)
    env[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return sig * env


def pizz_bass(f, gate):
    n = gate + int(0.25 * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * f * t
    sig = np.sin(ph) + 0.35 * np.sin(2 * ph) * np.exp(-t * 9) + 0.12 * np.sin(3 * ph) * np.exp(-t * 14)
    env = np.exp(-t * 4.0) * np.minimum(1, t / 0.004)
    rel = np.ones(n)
    rel[gate:] = np.exp(-np.arange(n - gate) / SR * 18)
    out = sig * env * rel
    out[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    return out


def soft_kick():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 48 + 70 * np.exp(-t * 30)
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11) * np.minimum(1, t / 0.002)
    sig[-200:] *= np.linspace(1, 0, 200)
    return sig


SOS_RIM = signal.butter(2, [1500, 4500], btype="bandpass", fs=SR, output="sos")


def rim():
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    sig = (signal.sosfilt(SOS_RIM, rng.standard_normal(n)) * 0.7 + np.sin(2 * np.pi * 820 * t) * 0.6) * np.exp(-t * 70)
    sig *= np.minimum(1, t / 0.0006)
    sig[-100:] *= np.linspace(1, 0, 100)
    return sig


# ---------------------------------------------------------------- 트랙

def render_flute():
    buf = np.zeros((L, 2))
    for i, (step, ln, m) in enumerate(parse_melody()):
        vel = 0.92 + 0.08 * np.sin(i * 2.3)
        add_wrapped(buf, pan(flute(mtof(m), int(ln * STEP * 0.93)), 0.05) * 0.17 * vel, step * STEP)
    return buf


def render_marimba():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        v = sorted(voice_range(t % 12, 62, 74, 60) for t in tones)
        seq = [v[0], v[1], v[2], v[1], v[0] + 12, v[2], v[1], v[2]]
        for i in range(8):
            p = -0.4 if i % 2 == 0 else -0.1
            vel = 0.075 if i % 2 == 0 else 0.05
            add_wrapped(buf, pan(marimba(mtof(seq[i])), p) * vel, (bar * 16 + i * 2) * STEP)
    return buf


def render_bass():
    buf = np.zeros((L, 2))
    for bar, (root, _) in enumerate(CHORDS):
        r = 36 + root
        pattern = [(0, r, 5), (6, r, 2), (8, r + 7, 3), (12, r + 12, 3)]
        if bar % 4 == 3:
            nxt = 36 + CHORDS[(bar + 1) % BARS][0]
            pattern[-1] = (12, nxt - 1, 3)   # 다음 근음 반음 아래로 이끄는 음
        for s, m, ln in pattern:
            add_wrapped(buf, pan(pizz_bass(mtof(m), ln * STEP), 0.0) * 0.26, (bar * 16 + s) * STEP)
    return buf


def render_pad():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        for t in tones:
            f = mtof(voice_range(t % 12, 57, 69, 60))
            sig = np.stack([soft_pad(f, 16 * STEP, -0.003), soft_pad(f, 16 * STEP, 0.003)], axis=1)
            add_wrapped(buf, sig * 0.022, bar * 16 * STEP)
    return buf


def render_comp():
    """후반 8마디 일렉트릭 피아노 뒷박 컴핑"""
    buf = np.zeros((L, 2))
    for bar in range(8, BARS):
        tones = CHORDS[bar][1]
        voicing = sorted(voice_range(t % 12, 55, 67, 48) for t in tones)
        for s in (2, 6, 10, 14):
            for j, m in enumerate(voicing):
                add_wrapped(buf, pan(epiano(mtof(m), int(STEP * 1.4), 0.55), 0.35) * 0.06, (bar * 16 + s) * STEP)
    return buf


def render_drums():
    buf = np.zeros((L, 2))
    k, rm = soft_kick(), rim()
    for bar in range(BARS):
        base = bar * 16
        for s in (0, 7, 10) if bar % 2 else (0, 10):
            add_wrapped(buf, pan(k, 0.0) * (0.34 if s == 0 else 0.24), (base + s) * STEP)
        fill = bar in (7, 15)
        for s in (4, 12) + ((14, 15) if fill else ()):
            add_wrapped(buf, pan(rm, 0.2) * (0.10 if s in (4, 12) else 0.06), (base + s) * STEP)
        for i in range(8):
            add_wrapped(buf, pan(shaker(0.032 if i % 2 else 0.018), 0.4), (base + i * 2) * STEP)
    return buf


# ---------------------------------------------------------------- 메인

def main():
    game = "--game" in sys.argv
    fl = render_flute() * (0.85 if game else 1.0)
    mar = render_marimba()
    bass = render_bass()
    pad = render_pad()
    comp = render_comp()
    drums = render_drums()

    fl_fx = fl + circular_delay(fl, STEP * 3, 0.25, taps=6) * 0.35      # 점8분 핑퐁 딜레이
    bass = circular_filter(bass, signal.butter(2, 1200, btype="lowpass", fs=SR, output="sos"))

    dry = fl_fx + mar + bass + pad + comp + drums
    send = fl_fx * 0.45 + mar * 0.35 + pad * 0.6 + comp * 0.4 + drums * 0.08
    mix = dry + circular_convolve(send, make_hall_ir(2.8)) * 0.32

    mix = circular_filter(mix, signal.butter(2, 30, btype="highpass", fs=SR, output="sos"))
    mix = circular_filter(mix, signal.butter(1, 11000, btype="lowpass", fs=SR, output="sos"))
    if game:
        mix = circular_filter(mix, signal.butter(2, 45, btype="highpass", fs=SR, output="sos"))
        mix = circular_filter(mix, peaking_sos(90, -4.0, 0.9))
        mix = circular_filter(mix, peaking_sos(1500, -2.5, 1.1))
    mix *= 10 ** (-1.0 / 20) / np.max(np.abs(mix))

    os.makedirs(OUT_DIR, exist_ok=True)
    if game:
        path = os.path.join(OUT_DIR, "trio_bgm_field_game.wav")
        write_wav_with_loop(path, mix, loop=True)
        dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "audio", "bgm_field.wav")
        shutil.copyfile(path, dst)
        print(f"wrote {path}  ({L} samples, {L / SR:.3f} s)")
        print(f"copied -> {os.path.normpath(dst)}")
        return
    loop_path = os.path.join(OUT_DIR, "trio_bgm_field_loop.wav")
    prev_path = os.path.join(OUT_DIR, "trio_bgm_field_preview_x2.wav")
    write_wav_with_loop(loop_path, mix, loop=True)
    write_wav_with_loop(prev_path, np.concatenate([mix, mix]), loop=False)
    print(f"wrote {loop_path}  ({L} samples, {L / SR:.3f} s)")
    print(f"wrote {prev_path}")


if __name__ == "__main__":
    main()
