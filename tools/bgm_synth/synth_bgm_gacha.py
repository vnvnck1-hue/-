"""
Trio Chess BGM #4 "보물상자(가챠)" - numpy/scipy 로만 합성하는 두근두근 반짝이는 상자 개봉 루프.

- 48 kHz / 100 BPM / 4/4 / 16 마디 (16분음표 = 정확히 7,200 샘플, 루프 38.4 초)
- G 장조 + 리디안(#4) 색채, 후반 Eb(bVI) -> F(bVII) -> Dsus4 -> D7 로 "뭐가 나올까" 긴장을 쌓고
  루프 처음 Gmaj7 로 해결된다.
- 셀레스타 멜로디 + 하프 아르페지오(전반 8분 -> 후반 16분) + 피치카토 베이스 + 패드
  + 글로켄 "반짝" 상행 스윕(4마디마다) + 소프트 킥/스냅/셰이커 + 루프 직전 리버스 스웰.
  후반 8마디는 플루트가 한 옥타브 아래에서 멜로디를 받친다.
- 원형 렌더링/이펙트는 synth_bgm.py, 악기 일부는 synth_bgm_calm.py / synth_bgm_field.py 것을 재사용.
- 출력: out/trio_bgm_gacha_loop.wav (smpl 루프 청크), out/trio_bgm_gacha_preview_x2.wav
- --game: 상자 화면용 믹스 out/trio_bgm_gacha_game.wav 를 만들고 godot/audio/bgm_gacha.wav 로 복사.
  상자 연출 효과음 자리를 비운다: 셀레스타/글로켄 -1.5 dB, 45 Hz 하이패스, 90 Hz -4 dB(thud/boom),
  1.5 kHz -3 dB(pop/chime), 3.2 kHz -2 dB(sparkle).

실행:  python synth_bgm_gacha.py          (감상용)
       python synth_bgm_gacha.py --game   (게임용)
"""
import os
import shutil
import sys

import numpy as np
from scipy import signal

from synth_bgm import (SR, OUT_DIR, peaking_sos, add_wrapped, pan, adsr, circular_filter, circular_delay,
                       circular_convolve, write_wav_with_loop, mtof, nmidi)
from synth_bgm_calm import celesta, soft_pad, shaker, voice_range, make_hall_ir
from synth_bgm_field import flute, pizz_bass, soft_kick

BPM = 100
STEP = SR * 60 // BPM // 4          # 7,200 샘플
assert STEP * BPM * 4 == SR * 60
BARS = 16
L = STEP * 16 * BARS
rng = np.random.default_rng(100)

# ---------------------------------------------------------------- 악보

Gmaj7, Em7, Cmaj7, D, Bm7, Am7, Ebmaj7, F6, Dsus4, D7 = (
    (7, [7, 11, 14, 18]), (4, [4, 7, 11, 14]), (0, [0, 4, 7, 11]), (2, [2, 6, 9]),
    (11, [11, 14, 18, 21]), (9, [9, 12, 16, 19]), (3, [3, 7, 10, 14]), (5, [5, 9, 12, 14]),
    (2, [2, 7, 9]), (2, [2, 6, 9, 12]))
CHORDS = [Gmaj7, Em7, Cmaj7, D, Gmaj7, Bm7, Cmaj7, Am7,
          Cmaj7, Bm7, Em7, Am7, Ebmaj7, F6, Dsus4, D7]     # D7 -> 루프 처음 Gmaj7 로 해결

MELODY = [
    "D6:2 B5:2 G5:2 B5:2 D6:3 F#6:1 E6:2 D6:2",
    "E6:3 D6:1 B5:4 G5:2 A5:2 B5:4",
    "C6:2 E6:2 G6:4 F#6:2 E6:2 D6:2 B5:2",       # Cmaj7 위 F# = 리디안 #11
    "A5:6 F#5:2 A5:2 D6:2 -:4",
    "D6:2 B5:2 G5:2 B5:2 D6:3 G6:1 F#6:2 D6:2",
    "F#6:3 E6:1 D6:4 B5:2 A5:2 B5:4",
    "E6:4 G6:2 E6:2 C6:2 D6:2 E6:4",
    "C6:3 B5:1 A5:4 E5:4 F#5:4",
    "G5:2 C6:2 E6:2 G6:2 B6:4 A6:2 G6:2",
    "F#6:6 D6:2 B5:4 D6:4",
    "G6:2 F#6:2 E6:2 D6:2 B5:4 E6:4",
    "C6:4 E6:2 C6:2 A5:4 -:4",
    "G5:2 Bb5:2 D6:2 G6:2 F6:4 D6:4",
    "A5:2 C6:2 F6:2 A6:2 G6:4 F6:4",
    "G6:4 D6:2 G6:2 A6:4 G6:4",
    "F#6:4 E6:2 D6:2 C6:2 A5:2 F#5:4",           # F#5 -> 루프 첫 음 D6
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

def harp(f):
    """하프: 가산 배음이 높은 것부터 빨리 사라지는 뜯는 소리"""
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for k, w in enumerate([1.0, 0.45, 0.22, 0.12, 0.06], start=1):
        if f * k < SR * 0.45:
            sig += w * np.sin(2 * np.pi * f * k * t + 0.3 * k) * np.exp(-t * (2.2 + 3.0 * k))
    env = np.minimum(1, t / 0.003)
    env[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR))
    return sig * env


def glock(f):
    """글로켄슈필: 맑은 사인 + 비정수 배음 짧게"""
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    sig = (np.sin(2 * np.pi * f * t) * np.exp(-t * 3.5)
           + 0.25 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 14)
           + 0.10 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 30))
    env = np.minimum(1, t / 0.001)
    env[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return sig * env


SOS_SNAP = signal.butter(2, [1800, 6000], btype="bandpass", fs=SR, output="sos")


def snap():
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    sig = signal.sosfilt(SOS_SNAP, rng.standard_normal(n)) * np.exp(-t * 55) * np.minimum(1, t / 0.0005)
    sig[-100:] *= np.linspace(1, 0, 100)
    return sig


SOS_SWELL = signal.butter(2, [2500, 9000], btype="bandpass", fs=SR, output="sos")


def swell(length):
    """리버스 심벌풍 노이즈 스웰 (끝에서 뚝 끊기며 다음 마디 첫 박으로)"""
    t = np.arange(length) / length
    sig = signal.sosfilt(SOS_SWELL, rng.standard_normal(length)) * t ** 3
    sig[-int(0.04 * SR):] *= np.linspace(1, 0, int(0.04 * SR)) ** 2
    return sig


# ---------------------------------------------------------------- 트랙

def render_celesta():
    buf = np.zeros((L, 2))
    for i, (step, ln, m) in enumerate(parse_melody()):
        vel = 0.9 + 0.1 * np.sin(i * 1.9)
        add_wrapped(buf, pan(celesta(mtof(m), int(ln * STEP * 0.9)), 0.1) * 0.19 * vel, step * STEP)
    return buf


def render_flute():
    """후반 8마디: 멜로디를 한 옥타브 아래에서 받친다"""
    buf = np.zeros((L, 2))
    for i, (step, ln, m) in enumerate(parse_melody()):
        if step < 8 * 16:
            continue
        add_wrapped(buf, pan(flute(mtof(m - 12), int(ln * STEP * 0.93)), -0.15) * 0.09, step * STEP)
    return buf


def render_harp():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        v = sorted(voice_range(t % 12, 55, 67, 48) for t in tones)
        up = v + [m + 12 for m in v]                      # 2옥타브 상행
        seq = up + up[-2:0:-1]                            # 위로 갔다가 내려온다
        dense = bar >= 8                                  # 후반은 16분으로 쏟아진다
        n = 16 if dense else 8
        for i in range(n):
            m = seq[i % len(seq)]
            p = -0.5 + 0.8 * (m - 55) / 24
            vel = (0.07 if i % (4 if dense else 2) == 0 else 0.05) * (0.85 if dense else 1.0)
            add_wrapped(buf, pan(harp(mtof(m)), p) * vel, (bar * 16 + i * (16 // n)) * STEP)
    return buf


def render_bass():
    buf = np.zeros((L, 2))
    for bar, (root, _) in enumerate(CHORDS):
        r = 36 + root if root < 5 else 24 + root          # F1..E2 범위
        pattern = [(0, r, 4), (6, r, 2), (8, r + 7, 4), (14, r + 12, 2)]
        if bar % 4 == 3:
            nxt = CHORDS[(bar + 1) % BARS][0]
            nr = 36 + nxt if nxt < 5 else 24 + nxt
            pattern[-1] = (14, nr - 1, 2)   # 다음 근음 반음 아래로 이끄는 음
        for s, m, ln in pattern:
            add_wrapped(buf, pan(pizz_bass(mtof(m), ln * STEP), 0.0) * 0.25, (bar * 16 + s) * STEP)
    return buf


def render_pad():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        for t in tones:
            f = mtof(voice_range(t % 12, 57, 69, 60))
            sig = np.stack([soft_pad(f, 16 * STEP, -0.004), soft_pad(f, 16 * STEP, 0.004)], axis=1)
            add_wrapped(buf, sig * (0.018 if bar < 12 else 0.024), bar * 16 * STEP)
    return buf


def render_sparkle():
    """4마디마다 마지막 박에 글로켄 상행 스윕 (상자 뚜껑이 반짝이는 느낌)"""
    buf = np.zeros((L, 2))
    for bar in (3, 7, 11, 15):
        tones = CHORDS[bar][1]
        v = sorted(voice_range(t % 12, 79, 91, 84) for t in tones)
        run = (v + [m + 12 for m in v])[:6]
        for i, m in enumerate(run):
            add_wrapped(buf, pan(glock(mtof(m)), -0.6 + 0.24 * i) * (0.04 + 0.006 * i),
                        bar * 16 * STEP + 12 * STEP + i * STEP * 2 // 3)
    return buf


def render_drums():
    buf = np.zeros((L, 2))
    k, sn = soft_kick(), snap()
    for bar in range(BARS):
        base = bar * 16
        kicks = (0, 8, 11) if bar % 2 else (0, 8)
        if bar >= 12:
            kicks = (0, 6, 8, 11) if bar < 15 else (0, 4, 8, 12, 14)   # 끝으로 갈수록 몰아친다
        for s in kicks:
            add_wrapped(buf, pan(k, 0.0) * (0.32 if s == 0 else 0.22), (base + s) * STEP)
        for s in (4, 12):
            add_wrapped(buf, pan(sn, -0.25) * 0.12, (base + s) * STEP)
        for i in range(16):
            v = 0.026 if i % 2 else 0.014
            if bar >= 8 or i % 2 == 0:                    # 전반은 8분, 후반은 16분 셰이커
                add_wrapped(buf, pan(shaker(v), 0.45), (base + i) * STEP)
    sw = swell(8 * STEP)                                  # 마지막 마디 후반 2박 -> 루프 첫 박
    add_wrapped(buf, pan(sw, 0.0) * 0.07, (BARS * 16 - 8) * STEP)
    return buf


# ---------------------------------------------------------------- 메인

def main():
    game = "--game" in sys.argv
    cel = render_celesta() * (0.84 if game else 1.0)
    fl = render_flute()
    harp_t = render_harp()
    bass = render_bass()
    pad = render_pad()
    spk = render_sparkle() * (0.84 if game else 1.0)
    drums = render_drums()

    cel_fx = cel + circular_delay(cel, STEP * 3, 0.28, taps=6) * 0.3       # 점8분 핑퐁 딜레이
    spk_fx = spk + circular_delay(spk, STEP * 2, 0.35, taps=5) * 0.4
    bass = circular_filter(bass, signal.butter(2, 1100, btype="lowpass", fs=SR, output="sos"))

    dry = cel_fx + fl + harp_t + bass + pad + spk_fx + drums
    send = cel_fx * 0.45 + fl * 0.5 + harp_t * 0.35 + pad * 0.6 + spk_fx * 0.6 + drums * 0.08
    mix = dry + circular_convolve(send, make_hall_ir(3.0)) * 0.34

    mix = circular_filter(mix, signal.butter(2, 30, btype="highpass", fs=SR, output="sos"))
    mix = circular_filter(mix, signal.butter(1, 12000, btype="lowpass", fs=SR, output="sos"))
    if game:
        mix = circular_filter(mix, signal.butter(2, 45, btype="highpass", fs=SR, output="sos"))
        mix = circular_filter(mix, peaking_sos(90, -4.0, 0.9))
        mix = circular_filter(mix, peaking_sos(1500, -3.0, 1.1))
        mix = circular_filter(mix, peaking_sos(3200, -2.0, 1.2))
    mix *= 10 ** (-1.0 / 20) / np.max(np.abs(mix))

    os.makedirs(OUT_DIR, exist_ok=True)
    if game:
        path = os.path.join(OUT_DIR, "trio_bgm_gacha_game.wav")
        write_wav_with_loop(path, mix, loop=True)
        dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "audio", "bgm_gacha.wav")
        shutil.copyfile(path, dst)
        print(f"wrote {path}  ({L} samples, {L / SR:.3f} s)")
        print(f"copied -> {os.path.normpath(dst)}")
        return
    loop_path = os.path.join(OUT_DIR, "trio_bgm_gacha_loop.wav")
    prev_path = os.path.join(OUT_DIR, "trio_bgm_gacha_preview_x2.wav")
    write_wav_with_loop(loop_path, mix, loop=True)
    write_wav_with_loop(prev_path, np.concatenate([mix, mix]), loop=False)
    print(f"wrote {loop_path}  ({L} samples, {L / SR:.3f} s)")
    print(f"wrote {prev_path}")


if __name__ == "__main__":
    main()
