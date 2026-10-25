"""Builds the deterministic test vowel used by VoiceFeaturesTests.swift and prints its features."""
import numpy as np
from features import extract, FEATURE_NAMES

def test_signal():
    sr = 44100
    n = int(sr * 3.0)
    t = np.arange(n) / sr
    # 140 Hz voice with 5 Hz vibrato (+-2 Hz) and 4 Hz loudness wobble, 5 harmonics.
    f0 = 140 + 2.0 * np.sin(2 * np.pi * 5 * t)
    phase = 2 * np.pi * np.cumsum(f0) / sr
    x = sum((0.6 / h) * np.sin(h * phase) for h in range(1, 6))
    x *= 0.5 * (1 + 0.1 * np.sin(2 * np.pi * 4 * t))
    # Deterministic noise from a simple LCG so Swift can make the exact same numbers.
    state = 12345
    noise = np.empty(n)
    for i in range(n):
        state = (1103515245 * state + 12345) % 2147483648
        noise[i] = state / 2147483648 - 0.5
    x = x + 0.01 * noise
    # 0.3 s of near-silence at each end, like a real recording.
    pad = int(0.3 * sr)
    x = np.concatenate([0.001 * noise[:pad], x, 0.001 * noise[:pad]])
    return x.astype(np.float32).astype(np.float64)

if __name__ == "__main__":
    f = extract(test_signal())
    for k in FEATURE_NAMES:
        print(f"{k}: {f[k]!r}")
