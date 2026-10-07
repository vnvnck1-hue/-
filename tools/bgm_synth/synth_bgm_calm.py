"""
Trio Chess BGM #2 "잔잔한 버전" - numpy/scipy 로만 합성하는 느리고 잔잔한 루프.

- 48 kHz / 72 BPM / 4/4 / 16 마디 (16분음표 = 정확히 10,000 샘플, 루프 53.333 초)
- F 장조, 메이저7·마이너7 위주 진행. 드럼 없이 일렉트릭 피아노·셀레스타·패드·베이스.
- 원형 렌더링/이펙트는 synth_bgm.py 의 헬퍼를 그대로 사용 (루프 끝 꼬리는 앞으로 감김).
- 출력: out/trio_bgm_calm_loop.wav (smpl 루프 청크), out/trio_bgm_calm_preview_x2.wav
- --game: 로비용 믹스 out/trio_bgm_calm_game.wav 를 만들고 godot/audio/bgm_lobby.wav 로 복사.
  로비 효과음(click 0.9 kHz, chime 0.9~2.6 kHz) 자리를 1.2 kHz 에서 살짝 비운다.

실행:  python synth_bgm_calm.py          (감상용)
       python synth_bgm_calm.py --game   (로비용)
"""
import os
import shutil
import sys

import numpy as np
from scipy import signal

from synth_bgm import (SR, OUT_DIR, peaking_sos, add_wrapped, pan, adsr, circular_filter, additive, harmonic_count,
                       circular_delay, circular_convolve, write_wav_with_loop, mtof, nmidi)

BPM = 72
STEP = SR * 60 // BPM // 4          # 10,000 샘플
assert STEP * BPM * 4 == SR * 60
BARS = 16
L = STEP * 16 * BARS
rng = np.random.default_rng(72)

# ---------------------------------------------------------------- 악보

CHORDS = [  # (근음 pitch class, 구성음 - C 기준 반음)
    (5, [5, 9, 12, 16]),    # Fmaj7
    (9, [9, 12, 16, 19]),   # Am7
    (2, [2, 5, 9, 12]),     # Dm7
    (10, [10, 14, 17, 21]),  # Bbmaj7
    (5, [5, 9, 12, 16]),    # Fmaj7
    (9, [9, 12, 16, 19]),   # Am7
    (2, [2, 5, 9, 12]),     # Dm7
    (0, [0, 5, 7, 10]),     # C7sus4
    (10, [10, 14, 17, 21]),  # Bbmaj7
    (0, [0, 4, 7, 14]),     # Cadd9
    (9, [9, 12, 16, 19]),   # Am7
    (2, [2, 5, 9, 12]),     # Dm7
    (7, [7, 10, 14, 17]),   # Gm7
    (4, [4, 7, 12, 16]),    # C/E
    (10, [10, 14, 17, 21]),  # Bbmaj7
    (0, [0, 5, 7, 10]),     # C7sus4 -> 루프 처음 Fmaj7 로 해결
]

MELODY = [
    "A5:6 G5:2 F5:4 C5:4",
    "E5:8 G5:4 A5:4",
    "F5:6 E5:2 D5:4 A4:4",
    "D5:12 -:4",
    "A5:6 C6:2 A5:4 G5:4",
    "E5:8 C5:4 E5:4",
    "F5:4 A5:4 D6:4 C6:4",
    "G5:12 -:4",
    "F5:4 D5:4 F5:4 A5:4",
    "G5:8 E5:4 D5:4",
    "C5:6 E5:2 A5:8",
    "F5:6 E5:2 D5:4 F5:4",
    "Bb5:8 A5:4 G5:4",
    "E5:8 G5:4 C6:4",
    "D6:6 C6:2 A5:4 F5:4",
    "G5:8 -:2 F5:2 E5:4",      # E5 -> 루프 첫 음 A5
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


def voice_range(pc, lo, hi, base):
    m = base + pc
    while m < lo:
        m += 12
    while m > hi:
        m -= 12
    return m


# ---------------------------------------------------------------- 악기

def celesta(f, gate):
    """셀레스타/뮤직박스 느낌: 사인 + 빨리 사라지는 배음, 살짝 FM 해머"""
    n = gate + int(1.2 * SR)
    t = np.arange(n) / SR
    ham = 0.6 * np.exp(-t * 40) * np.sin(2 * np.pi * f * 3 * t)
    sig = (np.sin(2 * np.pi * f * t + ham)
           + 0.22 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 3)
           + 0.08 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 6))
    env = np.exp(-t * 1.6) * np.minimum(1, t / 0.004)
    rel = np.ones(n)
    r0 = min(gate + int(0.25 * SR), n)
    rel[r0:] = np.exp(-np.arange(n - r0) / SR * 5)
    sig *= env * rel
    sig[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return sig


def epiano(f, gate, vel):
    """FM 로즈풍 일렉트릭 피아노"""
    n = gate + int(0.6 * SR)
    t = np.arange(n) / SR
    idx = (1.0 * np.exp(-t * 3.0) + 0.15) * (0.6 + 0.4 * vel)
    body = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    tine = 0.07 * vel * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 30) if f * 14 < SR * 0.45 else 0.0
    env = np.exp(-t * 0.9) * np.minimum(1, t / 0.003)
    rel = np.ones(n)
    rel[gate:] = np.exp(-np.arange(n - gate) / SR * 8)
    sig = (body + tine) * env * rel
    sig[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return sig * vel


def soft_pad(f, gate, detune):
    r = int(2.2 * SR)
    n = gate + r
    t = np.arange(n) / SR
    hk = min(harmonic_count(f * 1.01), 10)
    w = [1.0 / k * np.exp(-k / 1.8) for k in range(1, hk + 1)]
    sig = additive(2 * np.pi * f * (1 + detune) * t + rng.uniform(0, 2 * np.pi), w)
    return sig * adsr(n, 1.4 * SR, 1.5 * SR, 0.85, r, gate)


def round_bass(f, gate):
    r = int(0.4 * SR)
    n = gate + r
    ph = 2 * np.pi * f * np.arange(n) / SR
    sig = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    return sig * adsr(n, 0.025 * SR, 0.8 * SR, 0.7, r, gate)


def soft_pluck(f):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    sig = np.sin(2 * np.pi * f * t + 0.8 * np.exp(-t * 12) * np.sin(2 * np.pi * f * 2 * t))
    env = np.exp(-t * 4.5) * np.minimum(1, t / 0.006)
    env[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return sig * env


SOS_SHAKER = signal.butter(2, [4000, 9500], btype="bandpass", fs=SR, output="sos")


def shaker(vel):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    env = np.minimum(1, t / 0.012) * np.exp(-np.maximum(t - 0.012, 0) * 45)
    sig = signal.sosfilt(SOS_SHAKER, rng.standard_normal(n)) * env
    sig[-100:] *= np.linspace(1, 0, 100)
    return sig * vel


# ---------------------------------------------------------------- 트랙

def render_melody():
    buf = np.zeros((L, 2))
    for i, (step, ln, m) in enumerate(parse_melody()):
        vel = 0.9 + 0.1 * np.sin(i * 1.7)          # 고정된 미세 벨로시티 변화
        add_wrapped(buf, pan(celesta(mtof(m), int(ln * STEP * 0.95)), 0.08) * 0.20 * vel, step * STEP)
    return buf


def render_epiano():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        voicing = sorted(voice_range(t % 12, 53, 67, 48) for t in tones)
        for s, ln, vel in ((0, 10, 0.8), (10, 6, 0.55)):   # 1박 + 3박 뒷박 살짝
            for j, m in enumerate(voicing):
                strum = int(j * 0.012 * SR)                # 아주 약한 스트럼
                sig = np.concatenate([np.zeros(strum), epiano(mtof(m), ln * STEP, vel)])
                add_wrapped(buf, pan(sig, -0.15 + 0.1 * j) * 0.10, (bar * 16 + s) * STEP)
    # 오토팬: 루프 안에 정수 주기가 들어가도록 (이음새에서 위상 연속)
    cycles = round(0.3 * L / SR)
    lfo = 0.25 * np.sin(2 * np.pi * cycles * np.arange(L) / L)
    a = (lfo + 1) * np.pi / 4
    mono = buf.mean(axis=1)
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1) * np.sqrt(2)


def render_pad():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        for t in tones[:3]:
            f = mtof(voice_range(t % 12, 57, 70, 60))
            sig = np.stack([soft_pad(f, 16 * STEP, -0.003), soft_pad(f, 16 * STEP, 0.003)], axis=1)
            add_wrapped(buf, sig * 0.032, bar * 16 * STEP)
    return buf


def render_bass():
    buf = np.zeros((L, 2))
    for bar, (root, tones) in enumerate(CHORDS):
        r = 36 + root                      # C2~B2
        fifth = r + 7
        for s, m, ln in ((0, r, 9), (10, fifth if bar % 2 == 0 else r + 12, 5)):
            add_wrapped(buf, pan(round_bass(mtof(m), ln * STEP), 0.0) * 0.24, (bar * 16 + s) * STEP)
    return buf


def render_arp():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        if bar < 4:
            continue
        v = sorted(voice_range(t % 12, 64, 76, 60) for t in tones)
        seq = [v[0], v[1], v[2], v[3], v[0] + 12, v[3], v[2], v[1]]
        for i in range(8):
            p = -0.5 if i % 2 == 0 else 0.5
            add_wrapped(buf, pan(soft_pluck(mtof(seq[i])), p) * (0.045 if i % 4 == 0 else 0.032),
                        (bar * 16 + i * 2) * STEP)
    return circular_filter(buf, signal.butter(2, 3000, btype="lowpass", fs=SR, output="sos"))


def render_shaker():
    buf = np.zeros((L, 2))
    for bar in range(8, BARS):
        for i in range(8):
            vel = 0.035 if i % 2 == 1 else 0.02
            add_wrapped(buf, pan(shaker(vel), 0.35), (bar * 16 + i * 2) * STEP)
    return buf


def make_hall_ir(seconds=4.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t * 1.7)[:, None]
    ir = signal.sosfilt(signal.butter(2, 4200, btype="lowpass", fs=SR, output="sos"), ir, axis=0)
    ir[: int(0.025 * SR)] = 0
    return ir / np.sqrt(np.sum(ir ** 2, axis=0))


# ---------------------------------------------------------------- 메인

def main():
    mel = render_melody()
    ep = render_epiano()
    pad = render_pad()
    bass = render_bass()
    arp = render_arp()
    shk = render_shaker()

    mel_fx = mel + circular_delay(mel, STEP * 6, 0.28, taps=8) * 0.45   # 점4분 핑퐁 딜레이
    bass = circular_filter(bass, signal.butter(2, 900, btype="lowpass", fs=SR, output="sos"))

    dry = mel_fx + ep + pad + bass + arp + shk
    send = mel_fx * 0.6 + ep * 0.45 + pad * 0.7 + arp * 0.6 + shk * 0.3
    mix = dry + circular_convolve(send, make_hall_ir()) * 0.45

    mix = circular_filter(mix, signal.butter(2, 30, btype="highpass", fs=SR, output="sos"))
    mix = circular_filter(mix, signal.butter(1, 9000, btype="lowpass", fs=SR, output="sos"))   # 따뜻하게
    if "--game" in sys.argv:
        mix = circular_filter(mix, peaking_sos(1200, -2.5, 1.0))
    mix *= 10 ** (-1.0 / 20) / np.max(np.abs(mix))

    os.makedirs(OUT_DIR, exist_ok=True)
    if "--game" in sys.argv:
        path = os.path.join(OUT_DIR, "trio_bgm_calm_game.wav")
        write_wav_with_loop(path, mix, loop=True)
        dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "audio", "bgm_lobby.wav")
        shutil.copyfile(path, dst)
        print(f"wrote {path}  ({L} samples, {L / SR:.3f} s)")
        print(f"copied -> {os.path.normpath(dst)}")
        return
    loop_path = os.path.join(OUT_DIR, "trio_bgm_calm_loop.wav")
    prev_path = os.path.join(OUT_DIR, "trio_bgm_calm_preview_x2.wav")
    write_wav_with_loop(loop_path, mix, loop=True)
    write_wav_with_loop(prev_path, np.concatenate([mix, mix]), loop=False)
    print(f"wrote {loop_path}  ({L} samples, {L / SR:.3f} s)")
    print(f"wrote {prev_path}")


if __name__ == "__main__":
    main()
