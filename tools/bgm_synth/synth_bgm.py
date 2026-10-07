"""
Trio Chess BGM - 샘플/외부 음원 없이 numpy/scipy 로만 합성하는 루프 BGM.

- 48 kHz / 120 BPM / 4/4 / 16 마디 (= 정확히 32 초, 1,536,000 샘플)
- 모든 소리를 "원형 버퍼"에 렌더링: 루프 끝을 넘는 꼬리(릴리스, 딜레이, 리버브)는
  버퍼 앞쪽으로 감아서 더한다. 그래서 끝→처음으로 넘어갈 때 끊김이 없다.
- 출력: out/trio_bgm_loop.wav (smpl 루프 청크 포함), out/trio_bgm_preview_x2.wav (확인용 2회 반복)
- --game: 게임용 믹스 out/trio_bgm_game.wav 를 만들고 godot/audio/bgm_main.wav 로 복사한다.
  효과음(godot/scripts/sfx.gd)과 대역이 겹치는 킥·베이스 저역, 리드, 하이햇을 줄이고 EQ 로 자리를 비운 버전.

실행:  python synth_bgm.py          (감상용)
       python synth_bgm.py --game   (게임용)
"""
import os
import shutil
import struct
import sys

import numpy as np
from scipy import signal

SR = 48000
BPM = 120
STEP = SR * 60 // BPM // 4          # 16분음표 = 6000 샘플 (정수)
BARS = 16
STEPS_PER_BAR = 16
L = STEP * STEPS_PER_BAR * BARS     # 루프 길이 (샘플)
rng = np.random.default_rng(20261007)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


# ---------------------------------------------------------------- 유틸

def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


NOTE_IDX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nmidi(name):
    """'C#5' -> MIDI 번호"""
    n = NOTE_IDX[name[0]]
    i = 1
    if name[i] in "#b":
        n += 1 if name[i] == "#" else -1
        i += 1
    return n + 12 * (int(name[i:]) + 1)


def add_wrapped(buf, sig, start):
    """sig 를 buf[start:] 에 더하되, 루프 끝을 넘는 부분은 앞으로 감는다. buf: (루프 길이, 2)"""
    size = len(buf)
    start %= size
    n = len(sig)
    pos = 0
    while pos < n:
        s = (start + pos) % size
        k = min(n - pos, size - s)
        buf[s:s + k] += sig[pos:pos + k]
        pos += k


def pan(mono, p):
    """p: -1(좌) ~ +1(우), equal-power"""
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def adsr(n, a, d, s, r, gate):
    """샘플 단위 ADSR. gate = 노트 길이(샘플). 반환 길이 = gate + r"""
    a, d, r = max(int(a), 1), max(int(d), 1), max(int(r), 1)
    env = np.empty(gate + r)
    t = np.arange(gate)
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / d * 4))
    env[:gate] = e
    last = e[-1] if gate > 0 else 0.0
    env[gate:] = last * np.exp(-np.arange(r) / r * 6) * np.linspace(1, 0, r)
    return env[:n] if n < len(env) else env


def circular_filter(x, sos):
    """필터 상태가 루프를 가로질러 이어지도록: 3번 타일링해서 가운데만 사용"""
    tiled = np.concatenate([x, x, x], axis=0)
    y = signal.sosfilt(sos, tiled, axis=0)
    return y[len(x):2 * len(x)]


def additive(phase, weights):
    """밴드리밋 가산 합성. phase: 기본 위상 배열, weights: k=1.. 하모닉 가중치"""
    out = np.zeros_like(phase)
    for k, w in enumerate(weights, start=1):
        if w != 0.0:
            out += w * np.sin(k * phase)
    return out


def harmonic_count(f):
    return max(1, int((SR * 0.45) // f))


# ---------------------------------------------------------------- 악보

CHORDS = [  # 마디별 코드 (근음, 구성음)
    ("C", [0, 4, 7]), ("G", [7, 11, 14]), ("A", [9, 12, 16]), ("F", [5, 9, 12]),
    ("C", [0, 4, 7]), ("G", [7, 11, 14]), ("F", [5, 9, 12]), ("G", [7, 11, 14]),
    ("A", [9, 12, 16]), ("F", [5, 9, 12]), ("C", [0, 4, 7]), ("G", [7, 11, 14]),
    ("A", [9, 12, 16]), ("F", [5, 9, 12]), ("D", [2, 5, 9]), ("G", [7, 11, 14]),
]
CHORD_ROOT = {"C": 0, "D": 2, "F": 5, "G": 7, "A": 9}

MELODY = [
    # A 섹션
    "E5:2 G5:2 C6:4 B5:2 G5:2 E5:4",
    "D5:2 G5:2 B5:4 A5:2 G5:2 D5:4",
    "C5:2 E5:2 A5:4 G5:2 E5:2 C5:2 E5:2",
    "F5:4 A5:2 G5:2 F5:4 -:4",
    "E5:2 G5:2 C6:2 D6:2 E6:4 D6:2 C6:2",
    "B5:2 D6:2 B5:2 G5:2 D5:4 G5:4",
    "A5:2 C6:2 A5:2 F5:2 G5:2 A5:2 B5:4",
    "D6:6 B5:2 G5:4 -:4",
    # B 섹션
    "A5:4 C6:2 B5:2 A5:4 E5:4",
    "F5:2 G5:2 A5:2 C6:2 A5:4 -:4",
    "G5:4 E5:2 G5:2 C6:4 G5:4",
    "B5:2 A5:2 G5:2 D5:2 G5:8",
    "C6:2 B5:2 A5:2 E5:2 A5:4 C6:4",
    "D6:4 C6:2 A5:2 F5:4 A5:4",
    "F5:2 A5:2 D6:2 F6:2 E6:4 D6:4",
    "B5:4 D6:2 B5:2 G5:4 F5:2 D5:2",   # 마지막 D5 -> 루프 첫 음 E5 로 이어짐
]


def parse_melody():
    notes = []  # (step, length_steps, midi)
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

def lead_voice(f, gate):
    r = int(0.12 * SR)
    n = gate + r
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    phase = 2 * np.pi * np.cumsum(f * vib) / SR
    hk = min(harmonic_count(f * 1.01), 24)
    w = [(1.0 if k % 2 else 0.35) / k * np.exp(-k / 10) for k in range(1, hk + 1)]
    sig = additive(phase, w)
    env = adsr(n, 0.008 * SR, 0.18 * SR, 0.6, r, gate)
    return sig * env


def bass_voice(f, gate):
    r = int(0.05 * SR)
    n = gate + r
    phase = 2 * np.pi * f * np.arange(n) / SR
    hk = min(harmonic_count(f), 18)
    w = [1.0 / k * np.exp(-k / 4.5) for k in range(1, hk + 1)]
    sig = additive(phase, w) + 0.6 * np.sin(phase)
    env = adsr(n, 0.004 * SR, 0.12 * SR, 0.55, r, gate)
    return sig * env


def pluck_voice(f, gate):
    """FM 플럭 (아르페지오용)"""
    n = gate + int(0.35 * SR)
    t = np.arange(n) / SR
    idx = 2.2 * np.exp(-t * 18)
    mod = idx * np.sin(2 * np.pi * f * 2 * t)
    sig = np.sin(2 * np.pi * f * t + mod)
    env = np.exp(-t * 7) * np.minimum(1, t / 0.002)
    env[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return sig * env


def pad_voice(f, gate, detune):
    r = int(0.9 * SR)
    n = gate + r
    t = np.arange(n) / SR
    hk = min(harmonic_count(f * 1.01), 16)
    w = [1.0 / k * np.exp(-k / 3.0) for k in range(1, hk + 1)]
    ph0 = rng.uniform(0, 2 * np.pi)
    sig = additive(2 * np.pi * f * (1 + detune) * t + ph0, w)
    env = adsr(n, 0.35 * SR, 0.6 * SR, 0.8, r, gate)
    return sig * env


SOS_SNARE = signal.butter(2, [900, 7000], btype="bandpass", fs=SR, output="sos")
SOS_HAT = signal.butter(4, 7000, btype="highpass", fs=SR, output="sos")


def attack_ramp(sig, ms):
    k = max(int(ms * SR / 1000), 1)
    sig[:k] *= np.linspace(0, 1, k)
    return sig


def kick():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 9)
    click = np.exp(-t * 400) * 0.4
    sig = body + click
    sig[-200:] *= np.linspace(1, 0, 200)
    return attack_ramp(sig, 1.0)


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = signal.sosfilt(SOS_SNARE, rng.standard_normal(n)) * np.exp(-t * 22)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    sig = 0.9 * noise + 0.5 * tone
    sig[-200:] *= np.linspace(1, 0, 200)
    return attack_ramp(sig, 0.7)


def hat(open_=False):
    n = int((0.3 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    sig = signal.sosfilt(SOS_HAT, rng.standard_normal(n)) * np.exp(-t * (12 if open_ else 70))
    sig[-100:] *= np.linspace(1, 0, 100)
    return attack_ramp(sig, 0.5)


# ---------------------------------------------------------------- 트랙 렌더링

def render_lead():
    buf = np.zeros((L, 2))
    for step, ln, m in parse_melody():
        gate = int(ln * STEP * 0.92)
        add_wrapped(buf, pan(lead_voice(mtof(m), gate), 0.0) * 0.30, step * STEP)
    return buf


def render_bass():
    buf = np.zeros((L, 2))
    for bar, (root, _) in enumerate(CHORDS):
        r = 36 + CHORD_ROOT[root]          # C2 기준
        if r > 43:
            r -= 12
        pattern = [(0, r), (2, r + 12), (4, r), (6, r + 12), (8, r), (10, r + 12), (12, r + 7), (14, r + 12)]
        if bar % 4 == 3:                   # 4 마디마다 걷는 베이스
            pattern[-2:] = [(12, r + 7), (14, r + 10)]
        for s, m in pattern:
            add_wrapped(buf, pan(bass_voice(mtof(m), int(STEP * 1.7)), 0.0) * 0.32,
                        (bar * 16 + s) * STEP)
    return buf


def render_arp():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        if bar < 2:                        # 도입부 두 마디는 아르페지오 쉼
            continue
        seq = [tones[0], tones[1], tones[2], tones[1], tones[0] + 12, tones[2], tones[1], tones[2]]
        for i in range(16):
            m = 60 + seq[i % 8]
            p = -0.45 if i % 2 == 0 else 0.45
            vel = 0.09 if i % 4 == 0 else 0.06
            add_wrapped(buf, pan(pluck_voice(mtof(m), STEP), p) * vel, (bar * 16 + i) * STEP)
    return buf


def render_pad():
    buf = np.zeros((L, 2))
    for bar, (_, tones) in enumerate(CHORDS):
        gate = STEP * 16
        for tt in tones:
            m = 60 + tt - 12 if tt > 9 else 60 + tt
            f = mtof(m)
            left = pad_voice(f, gate, -0.004)
            right = pad_voice(f, gate, +0.004)
            add_wrapped(buf, np.stack([left, right], axis=1) * 0.045, bar * 16 * STEP)
    return buf


def render_drums():
    kbuf, sbuf, hbuf = np.zeros((L, 2)), np.zeros((L, 2)), np.zeros((L, 2))
    k = kick()
    snare()   # 난수 소비 순서 유지용 (기존 렌더와 동일한 노이즈를 얻기 위함)
    for bar in range(BARS):
        base = bar * 16
        kicks = [0, 8] + ([10] if bar % 2 == 1 else [])
        for s in kicks:
            add_wrapped(kbuf, pan(k, 0.0) * 0.55, (base + s) * STEP)
        fill = bar in (7, 15)
        snares = [4, 12] + ([13, 14, 15] if fill else [])
        for s in snares:
            vel = 0.30 if s in (4, 12) else 0.16 + 0.04 * (s - 13)
            add_wrapped(sbuf, pan(snare(), 0.05) * vel, (base + s) * STEP)
        for s in range(0, 16, 2):
            if fill and s >= 12:
                continue
            open_ = (s == 14 and bar % 4 == 1)
            vel = 0.10 if s % 4 == 2 else 0.065
            add_wrapped(hbuf, pan(hat(open_), 0.3) * vel, (base + s) * STEP)
    return kbuf, sbuf, hbuf


# ---------------------------------------------------------------- 이펙트 (모두 원형)

def circular_delay(x, delay_samples, feedback, taps=10, ping_pong=True):
    y = np.zeros_like(x)
    g = 1.0
    for n in range(1, taps + 1):
        g *= feedback
        tap = np.roll(x, n * delay_samples, axis=0)   # np.roll 은 원형
        if ping_pong and n % 2 == 1:
            tap = tap[:, ::-1]
        y += g * tap
    return y


def make_reverb_ir(seconds=2.2):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t * 3.2)[:, None]
    sos = signal.butter(2, 5500, btype="lowpass", fs=SR, output="sos")
    ir = signal.sosfilt(sos, ir, axis=0)
    ir[: int(0.012 * SR)] = 0                         # 프리딜레이 12 ms
    return ir / np.sqrt(np.sum(ir ** 2, axis=0))


def circular_convolve(x, ir):
    """루프 길이 FFT 로 컨볼루션 = 원형 컨볼루션 (리버브 꼬리가 앞으로 감김)"""
    n = len(x)
    X = np.fft.rfft(x, n=n, axis=0)
    H = np.fft.rfft(ir, n=n, axis=0)
    return np.fft.irfft(X * H, n=n, axis=0)


# ---------------------------------------------------------------- WAV 출력 (smpl 루프 청크 포함)

def write_wav_with_loop(path, data, loop=True, sr=SR):
    pcm = np.clip(np.round(data * 32767), -32768, 32767).astype("<i2")
    ch = pcm.shape[1]
    frames = pcm.shape[0]
    fmt = struct.pack("<HHIIHH", 1, ch, sr, sr * ch * 2, ch * 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt
    raw = pcm.tobytes()
    body += b"data" + struct.pack("<I", len(raw)) + raw
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)   # 전체 구간 루프 (end 포함)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as fp:
        fp.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def peaking_sos(f0, gain_db, q):
    """RBJ 피킹 EQ 바이쿼드"""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    den = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return np.array([[b[0] / den[0], b[1] / den[0], b[2] / den[0], 1.0, den[1] / den[0], den[2] / den[0]]])


# ---------------------------------------------------------------- 메인

# 스템 게인 (선형). game: 효과음과 겹치는 대역을 비운 게임용 밸런스
MIXES = {
    "listen": dict(lead=1.0, bass=1.0, arp=1.0, pad=1.0, kick=1.0, snare=1.0, hat=1.0),
    "game":   dict(lead=0.72, bass=0.75, arp=0.85, pad=1.1, kick=0.5, snare=0.75, hat=0.6),
}

GODOT_BGM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "audio", "bgm_main.wav")


def main():
    game = "--game" in sys.argv
    g = MIXES["game" if game else "listen"]

    lead = render_lead() * g["lead"]
    bass = render_bass() * g["bass"]
    arp = render_arp() * g["arp"]
    pad = render_pad() * g["pad"]
    kbuf, sbuf, hbuf = render_drums()
    drums = kbuf * g["kick"] + sbuf * g["snare"] + hbuf * g["hat"]

    lead_fx = lead + circular_delay(lead, STEP * 3, 0.32) * 0.5     # 점8분 핑퐁 딜레이
    if game:   # 리드 고역을 눌러 UI 효과음(pop/chime/click 0.5~2.6 kHz) 위로 튀지 않게
        lead_fx = circular_filter(lead_fx, signal.butter(2, 3200, btype="lowpass", fs=SR, output="sos"))
    arp = circular_filter(arp, signal.butter(1, 250, btype="highpass", fs=SR, output="sos"))
    bass = circular_filter(bass, signal.butter(2, 1800, btype="lowpass", fs=SR, output="sos"))

    dry = lead_fx + bass + arp + pad + drums
    send = lead_fx * 0.35 + arp * 0.5 + pad * 0.6 + drums * 0.08
    wet = circular_convolve(send, make_reverb_ir()) * 0.35
    mix = dry + wet

    if game:
        mix = circular_filter(mix, signal.butter(2, 45, btype="highpass", fs=SR, output="sos"))
        mix = circular_filter(mix, peaking_sos(90, -4.0, 0.9))     # thud/boom(35~210 Hz) 자리
        mix = circular_filter(mix, peaking_sos(1500, -3.0, 1.1))   # pop/chime/click 자리
        mix *= 10 ** (-1.0 / 20) / np.max(np.abs(mix))   # 다이내믹 유지 (새추레이션 없음), 피크 -1 dBFS
    else:
        mix = circular_filter(mix, signal.butter(2, 25, btype="highpass", fs=SR, output="sos"))  # DC/초저역 제거
        mix /= np.max(np.abs(mix))
        mix = np.tanh(mix * 1.4) / np.tanh(1.4)          # 부드러운 새추레이션 (무기억 → 이음새 영향 없음)
        mix *= 10 ** (-1.0 / 20) / np.max(np.abs(mix))   # 피크 -1 dBFS

    os.makedirs(OUT_DIR, exist_ok=True)
    if game:
        loop_path = os.path.join(OUT_DIR, "trio_bgm_game.wav")
        write_wav_with_loop(loop_path, mix, loop=True)
        os.makedirs(os.path.dirname(GODOT_BGM), exist_ok=True)
        shutil.copyfile(loop_path, GODOT_BGM)
        print(f"wrote {loop_path}  ({L} samples, {L / SR:.3f} s)")
        print(f"copied -> {os.path.normpath(GODOT_BGM)}")
        return
    loop_path = os.path.join(OUT_DIR, "trio_bgm_loop.wav")
    prev_path = os.path.join(OUT_DIR, "trio_bgm_preview_x2.wav")
    write_wav_with_loop(loop_path, mix, loop=True)
    write_wav_with_loop(prev_path, np.concatenate([mix, mix]), loop=False)
    print(f"wrote {loop_path}  ({L} samples, {L / SR:.3f} s)")
    print(f"wrote {prev_path}")


if __name__ == "__main__":
    main()
