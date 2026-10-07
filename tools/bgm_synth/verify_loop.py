"""루프 WAV 검증: 길이/포맷, smpl 청크, 클리핑, 이음새 불연속 여부."""
import os
import struct
import sys

import numpy as np
from scipy.io import wavfile

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "trio_bgm_loop.wav")
sr, x = wavfile.read(path)
x = x.astype(np.float64) / 32768
n = len(x)
print(f"format: {sr} Hz, {x.shape[1]} ch, {n} frames, {n / sr:.4f} s")

raw = open(path, "rb").read()
i = raw.find(b"smpl")
if i >= 0:
    start, end = struct.unpack("<II", raw[i + 8 + 36 + 8:i + 8 + 36 + 16])
    print(f"smpl loop: {start} .. {end} (frames-1 = {n - 1})")
else:
    print("smpl loop: none")

peak = np.max(np.abs(x))
print(f"peak: {20 * np.log10(peak):.2f} dBFS, clipped samples: {int(np.sum(np.abs(x) >= 0.9999))}")

# 1) 이음새 1샘플 점프: 끝 -> 처음 차이가 전체 샘플 간 차이 분포의 어디쯤인지
d = np.abs(np.diff(x, axis=0)).max(axis=1)
seam = np.abs(x[0] - x[-1]).max()
pct = (d < seam).mean() * 100
print(f"seam jump |x[0]-x[-1]| = {seam:.5f}  (percentile among all steps: {pct:.1f}%, median {np.median(d):.5f}, max {d.max():.5f})")

# 2) 고역 에너지(2차 차분) — 클릭은 고역 스파이크로 나타남.
#    이음새 주변 창을 같은 박 위치(매 마디 시작)의 창들과 비교한다.
looped = np.concatenate([x, x])
hp = np.abs(np.diff(looped, n=2, axis=0)).max(axis=1)
w = 256
bar = n // 16
def win(c):
    return hp[c - w:c + w].max()
seam_val = win(n)
others = [win(n + k * bar) for k in range(1, 16)]
print(f"2nd-diff peak around seam: {seam_val:.5f}  | other bar starts: min {min(others):.5f} median {np.median(others):.5f} max {max(others):.5f}")

# 3) RMS 연속성: 이음새 직전/직후 50 ms
q = int(0.05 * sr)
rb = np.sqrt(np.mean(x[-q:] ** 2)); ra = np.sqrt(np.mean(x[:q] ** 2))
print(f"RMS last 50ms {20*np.log10(rb):.2f} dB / first 50ms {20*np.log10(ra):.2f} dB")

# 4) 1샘플 점프를 다른 마디 시작점(같은 악기 패턴이 겹치는 곳)과 비교
bar_jumps = [np.abs(x[k * bar] - x[k * bar - 1]).max() for k in range(1, 16)]
print(f"1-sample jump at other bar starts: min {min(bar_jumps):.5f} median {np.median(bar_jumps):.5f} max {max(bar_jumps):.5f}")

ok = seam <= max(bar_jumps) * 1.05 and seam_val <= max(others) * 1.05
print("RESULT:", "SEAMLESS" if ok else "CHECK SEAM")
