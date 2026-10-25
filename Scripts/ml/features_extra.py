"""
Extra candidate features (experiment): MFCC statistics and spectral shape from the same
20 analysis frames used for CPP. Kept separate so we only port them to Swift if they help
on held-out speakers.
"""
import numpy as np
from features import (SR, CPP_N, HOP, CPP_FRAMES, frame_rms_db, percentile, voiced_mask,
                      yin, MAX_FRAMES)

N_MELS = 26
N_MFCC = 13
EXTRA_NAMES = [f"mfcc{i}_mean" for i in range(1, N_MFCC)] + [f"mfcc{i}_std" for i in range(1, N_MFCC)] + \
              ["centroid", "rolloff", "flatness"]


def mel(f):
    return 2595 * np.log10(1 + f / 700)


def mel_bank():
    N = CPP_N
    lo, hi = mel(50), mel(8000)
    pts = 700 * (10 ** (np.linspace(lo, hi, N_MELS + 2) / 2595) - 1)
    bins = np.floor((N + 1) * pts / SR).astype(int)
    fb = np.zeros((N_MELS, N // 2 + 1))
    for m in range(1, N_MELS + 1):
        a, b, c = bins[m - 1], bins[m], bins[m + 1]
        for k in range(a, b):
            fb[m - 1, k] = (k - a) / max(b - a, 1)
        for k in range(b, c):
            fb[m - 1, k] = (c - k) / max(c - b, 1)
    return fb


FB = mel_bank()
DCT = np.array([[np.cos(np.pi * i * (j + 0.5) / N_MELS) for j in range(N_MELS)] for i in range(N_MFCC)])


def extra(x, starts):
    N = CPP_N
    w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(N) / N)
    freqs = np.arange(N // 2 + 1) * SR / N
    mf, cen, rol, flat = [], [], [], []
    for s in starts:
        seg = x[s:s + N]
        if len(seg) < N:
            continue
        P = np.abs(np.fft.rfft(seg * w)) ** 2
        mf.append(DCT @ np.log(FB @ P + 1e-10))
        band = (freqs > 0) & (freqs <= 8000)
        Pb, fb_ = P[band], freqs[band]
        cen.append((Pb * fb_).sum() / (Pb.sum() + 1e-12))
        c = np.cumsum(Pb)
        rol.append(fb_[np.searchsorted(c, 0.85 * c[-1])])
        flat.append(np.exp(np.mean(np.log(Pb + 1e-12))) / (np.mean(Pb) + 1e-12))
    mf = np.array(mf)
    out = {}
    for i in range(1, N_MFCC):
        out[f"mfcc{i}_mean"] = float(mf[:, i].mean())
        out[f"mfcc{i}_std"] = float(mf[:, i].std(ddof=1)) if len(mf) > 1 else 0.0
    out["centroid"] = float(np.mean(cen)) / 1000
    out["rolloff"] = float(np.mean(rol)) / 1000
    out["flatness"] = float(np.mean(flat))
    return out
