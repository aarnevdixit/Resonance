"""
Formant features (tongue and jaw position) from an LPC spectral envelope.

Why: in bulbar ALS the tongue moves less, so the vowel /i/ ("eee") loses its high second
formant (F2) and /a/ and /i/ sound more alike. Vashkevich & Rushkevich (2021) found F2 of /i/
among the most useful features.

Method (kept simple so the Swift port is exact):
1. Resample to 11,025 Hz by averaging blocks of 4 samples (simple low-pass + decimate).
2. For the same evenly spaced frames used for CPP: 1024-sample (~93 ms at 11 kHz) frames,
   pre-emphasis 0.97, Hann window, autocorrelation LPC order 12 (Levinson-Durbin).
3. Evaluate the LPC envelope 1/|A(f)|^2 on a 5 Hz grid from 150 to 4000 Hz and take local
   maxima narrower than 500 Hz at half power as formant candidates. F1 = first peak in 200-1000 Hz, F2 = first peak above F1+200 Hz
   within 700-3200 Hz.
4. Report the median F1 and F2 over frames (Hz / 1000).
"""
import numpy as np

SR_LOW = 44100 / 4
ORDER = 12
N = 1024
MAX_BW = 500.0   # Hz; real formants are sharp, broad LPC bumps are fitting artifacts
GRID = 5.0


def levinson(r, order):
    a = np.zeros(order + 1); a[0] = 1.0
    e = r[0]
    if e <= 0:
        return None
    for i in range(1, order + 1):
        acc = r[i] + sum(a[j] * r[i - j] for j in range(1, i))
        k = -acc / e
        a_new = a.copy()
        for j in range(1, i):
            a_new[j] = a[j] + k * a[i - j]
        a_new[i] = k
        a = a_new
        e *= (1 - k * k)
        if e <= 0:
            return None
    return a


def half_power_width(env, i):
    """Width in Hz of the envelope peak at grid index i, measured where it falls to half power.
    A side that never falls to half power inside the grid counts up to the grid edge."""
    half = env[i] / 2
    lo = i
    while lo > 0 and env[lo] > half:
        lo -= 1
    hi = i
    while hi < len(env) - 1 and env[hi] > half:
        hi += 1
    return (hi - lo) * GRID


def frame_formants(seg):
    seg = np.append(seg[0], seg[1:] - 0.97 * seg[:-1])
    w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(N) / N)
    s = seg * w
    r = np.array([np.dot(s[:N - k], s[k:]) for k in range(ORDER + 1)])
    a = levinson(r, ORDER)
    if a is None:
        return None, None
    freqs = np.arange(150, 4001, 5.0)
    k = np.arange(ORDER + 1)
    env = []
    for f in freqs:
        om = 2 * np.pi * f / SR_LOW
        re = np.sum(a * np.cos(om * k)); im = -np.sum(a * np.sin(om * k))
        env.append(1.0 / (re * re + im * im + 1e-18))
    env = np.array(env)
    peaks = [freqs[i] for i in range(1, len(env) - 1)
             if env[i] > env[i - 1] and env[i] >= env[i + 1] and half_power_width(env, i) <= MAX_BW]
    f1 = next((p for p in peaks if 200 <= p <= 1000), None)
    if f1 is None:
        return None, None
    f2 = next((p for p in peaks if p >= f1 + 200 and 700 <= p <= 3200), None)
    return f1, f2


def formants(x44, starts44):
    """x44: level-normalized 44.1 kHz signal; starts44: frame starts (same frames as CPP)."""
    n = len(x44) // 4
    x = x44[:n * 4].reshape(n, 4).mean(axis=1)
    f1s, f2s = [], []
    for s in starts44:
        s4 = s // 4
        seg = x[s4:s4 + N]
        if len(seg) < N:
            continue
        f1, f2 = frame_formants(seg)
        if f1 is not None:
            f1s.append(f1)
        if f2 is not None:
            f2s.append(f2)
    F1 = float(np.median(f1s)) / 1000 if f1s else np.nan
    F2 = float(np.median(f2s)) / 1000 if f2s else np.nan
    return F1, F2
