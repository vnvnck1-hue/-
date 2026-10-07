"""Godot Movie Maker(.avi) 녹화에서 오디오를 뽑아 게임 내 최종 믹스를 검증한다.

사용: python analyze_recording.py rec.avi [음악 시작 오프셋 추정용 BGM wav]
- 전체 피크/클리핑
- 음악만 나오는 구간 vs 효과음 구간 레벨
- 녹화 안에서 루프 이음새(곡 시작 + 32 s) 전후 연속성
"""
import os
import struct
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile


def read_avi_audio(path):
    data = open(path, "rb").read()
    # strf(auds) 에서 WAVEFORMATEX 읽기
    i = data.find(b"auds")
    j = data.find(b"strf", i)
    fmt_tag, ch, sr, _, align, bits = struct.unpack("<HHIIHH", data[j + 8:j + 24])
    assert fmt_tag == 1 and bits == 16, (fmt_tag, bits)
    chunks = []
    pos = data.find(b"movi")
    while True:
        k = data.find(b"01wb", pos)
        if k < 0:
            break
        size = struct.unpack("<I", data[k + 4:k + 8])[0]
        chunks.append(data[k + 8:k + 8 + size])
        pos = k + 8 + size + (size & 1)
    pcm = np.frombuffer(b"".join(chunks), dtype="<i2").reshape(-1, ch)
    return sr, pcm.astype(np.float64) / 32768


def db(x):
    return 20 * np.log10(max(float(x), 1e-9))


here = os.path.dirname(os.path.abspath(__file__))
rec = sys.argv[1]
bgm_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "out", "trio_bgm_game.wav")
sr, x = read_avi_audio(rec)
x = x[: len(x) - int(0.2 * sr)]   # 마지막 0.2 s 는 엔진 종료 순간의 잡음이라 제외
print(f"recording: {sr} Hz, {x.shape[1]} ch, {len(x) / sr:.2f} s")
print(f"peak {db(np.max(np.abs(x))):.2f} dBFS, samples >= -0.5 dBFS: {int(np.sum(np.abs(x) >= 10 ** (-0.5 / 20)))}")

# BGM 원본과 상관으로 음악 시작 지점(오프셋) 찾기
bsr, b = wavfile.read(bgm_path)
b = b.astype(np.float64) / 32768
if bsr != sr:
    b = signal.resample_poly(b, sr, bsr, axis=0)
mono_x, mono_b = x.mean(axis=1), b.mean(axis=1)
seg = mono_b[sr * 2: sr * 6]          # 곡 2~6 초 구간을 녹화에서 찾는다
corr = signal.fftconvolve(mono_x[: sr * 12], seg[::-1], mode="valid")
off = int(np.argmax(corr)) - sr * 2
print(f"music starts at recording t = {off / sr:.3f} s")

# 음악 단독 성분을 빼서 효과음 성분 추정: 녹화 = g(t) * bgm + sfx
period = len(mono_b)
idx = (np.arange(len(mono_x)) - off) % period
ref = mono_b[idx]
ref[: max(off, 0)] = 0
win = int(0.4 * sr)
gains, sfx_rms, mus_rms = [], [], []
for s in range(max(off, 0) + 2 * sr, len(mono_x) - win, win):   # 페이드인 이후
    r, y = ref[s:s + win], mono_x[s:s + win]
    g = np.dot(r, y) / np.dot(r, r)
    gains.append(g)
    resid = y - g * r
    sfx_rms.append(np.sqrt(np.mean(resid ** 2)))
    mus_rms.append(np.sqrt(np.mean((g * r) ** 2)))
gains = np.array(gains)
print(f"music gain vs file: median {db(np.median(gains)):.1f} dB, min {db(gains.min()):.1f} dB (ducking depth {db(np.median(gains)) - db(gains.min()):.1f} dB)")
print(f"music short-term RMS in game: median {db(np.median(mus_rms)):.1f} dBFS")
busy = np.array(sfx_rms) > np.median(sfx_rms)
print(f"SFX residual short-term RMS: median {db(np.median(sfx_rms)):.1f}, busy-window median {db(np.median(np.array(sfx_rms)[busy])):.1f}, max {db(max(sfx_rms)):.1f} dBFS")
print(f"=> SFX(busy) over music: {db(np.median(np.array(sfx_rms)[busy])) - db(np.median(mus_rms)):+.1f} dB")

# 루프 이음새: 녹화 안에서 곡이 처음으로 다시 시작되는 지점
seam = off + period
if seam < len(x) - sr:
    w = int(0.03 * sr)
    pre, post = mono_x[seam - w:seam], mono_x[seam:seam + w]
    rpre, rpost = mono_b[-w:], mono_b[:w]
    gp = np.dot(rpre, pre) / np.dot(rpre, rpre)
    gq = np.dot(rpost, post) / np.dot(rpost, rpost)
    err = np.sqrt(np.mean((np.concatenate([pre, post]) - np.concatenate([rpre * gp, rpost * gq])) ** 2))
    print(f"loop seam at t = {seam / sr:.3f} s: jump {np.abs(x[seam] - x[seam - 1]).max():.5f} "
          f"(median step {np.median(np.abs(np.diff(mono_x))):.5f}); "
          f"match to file across seam: gain {gp:.4f}/{gq:.4f}, residual {db(err):.1f} dBFS")
else:
    print("recording too short to include loop seam")
