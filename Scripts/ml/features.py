"""
Resonance voice features (reference implementation).

This file is the exact Python twin of Resonance/Services/Audio/VoiceFeatures.swift.
Every step (frame sizes, thresholds, ordering) matches the Swift code so a model trained
here behaves the same on the iPhone. A parity unit test in Swift checks this.

Input: mono float signal in [-1, 1] at 44,100 Hz (a sustained "ahh").
Output: 10 features describing voice stability and quality.
"""
import numpy as np

SR = 44100
FRAME_DB = 1102          # 25 ms, for voiced/unvoiced detection
HOP = 441                # 10 ms
PITCH_FRAME = 1764       # 40 ms
MIN_LAG = int(SR / 400)  # 110
MAX_LAG = int(SR / 75)   # 588
YIN_THRESHOLD = 0.15
MAX_FRAMES = 600         # analyze at most 6 s from the middle of the vowel
CPP_N = 2048
CPP_FRAMES = 20
MIN_LOUD_DB = -55.0      # quietest training recording is about -38 dBFS

FEATURE_NAMES = [
    "f0StdSemi",      # pitch variation (semitones)
    "jitter",         # frame-to-frame period change (%)
    "shimmer",        # frame-to-frame amplitude change (%)
    "aperiodicity",   # how noisy the voice is (YIN dip, 0 = perfectly periodic)
    "voicedRatio",    # share of analyzed frames with a clear pitch
    "f0Tremor",       # share of pitch-contour energy at 3-12 Hz (tremor / vibrato)
    "ampTremor",      # share of loudness-contour energy at 3-12 Hz
    "ampStdDb",       # loudness steadiness (dB)
    "cpp",            # cepstral peak prominence (dB), lower = breathier / rougher
    "spectralTilt",   # energy below 1 kHz vs 1-4 kHz (dB)
]


def to_db(rms):
    return 20.0 * np.log10(rms + 1e-9)


def frame_rms_db(x, frame=FRAME_DB, hop=HOP):
    if len(x) < frame:
        return np.array([to_db(np.sqrt(np.mean(x ** 2)))])
    n = (len(x) - frame) // hop + 1
    out = np.empty(n)
    for i in range(n):
        seg = x[i * hop:i * hop + frame]
        out[i] = to_db(np.sqrt(np.mean(seg ** 2)))
    return out


def percentile(v, p):
    s = np.sort(v)
    pos = p / 100 * (len(s) - 1)
    lo = int(np.floor(pos))
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def voiced_mask(db, floor, margin=15.0, min_gap=10):
    mask = db > floor + margin
    i = 0
    n = len(mask)
    while i < n:
        if mask[i]:
            i += 1
            continue
        start = i
        while i < n and not mask[i]:
            i += 1
        if start > 0 and i < n and (i - start) < min_gap:
            mask[start:i] = True
    return mask


def yin(frame):
    """Returns (f0 or None, aperiodicity at the chosen lag)."""
    if np.sqrt(np.mean(frame ** 2)) <= 1e-4:
        return None, None
    W = len(frame) - MAX_LAG - 1
    d = np.zeros(MAX_LAG + 2)
    base = frame[:W]
    for tau in range(1, MAX_LAG + 2):
        diff = frame[tau:tau + W] - base
        d[tau] = np.dot(diff, diff)
    dp = np.ones(MAX_LAG + 2)
    running = 0.0
    for tau in range(1, MAX_LAG + 2):
        running += d[tau]
        dp[tau] = d[tau] * tau / running if running > 0 else 1.0
    tau = MIN_LAG
    found = None
    while tau <= MAX_LAG:
        if dp[tau] < YIN_THRESHOLD:
            while tau + 1 <= MAX_LAG and dp[tau + 1] < dp[tau]:
                tau += 1
            found = tau
            break
        tau += 1
    if found is None:
        return None, None
    refined = float(found)
    if 1 < found < MAX_LAG + 1:
        a, b, c = dp[found - 1], dp[found], dp[found + 1]
        den = a - 2 * b + c
        if abs(den) > 1e-12:
            shift = 0.5 * (a - c) / den
            if abs(shift) < 1:
                refined += shift
    f0 = SR / refined
    if not (75 <= f0 <= 400):
        return None, None
    return f0, float(dp[found])


def band_ratio(series, rate, low=3.0, high=12.0, total_low=1.0, total_high=25.0):
    """Share of contour power between low and high Hz, out of total_low..total_high Hz."""
    n = len(series)
    if n < 32:
        return 0.0
    t = np.arange(n, dtype=float)
    # remove linear trend
    tm, sm = t.mean(), series.mean()
    sxx = np.sum((t - tm) ** 2)
    slope = np.sum((t - tm) * (series - sm)) / sxx if sxx > 0 else 0.0
    resid = series - (sm + slope * (t - tm))
    band = total = 0.0
    for k in range(1, n // 2 + 1):
        w = 2 * np.pi * k / n
        re = np.sum(resid * np.cos(w * t))
        im = -np.sum(resid * np.sin(w * t))
        p = re * re + im * im
        f = k * rate / n
        if total_low <= f <= total_high:
            total += p
            if low <= f <= high:
                band += p
    return band / total if total > 0 else 0.0


def cpp_and_tilt(x, starts):
    """Mean cepstral peak prominence and spectral tilt over the given frame starts."""
    N = CPP_N
    n_idx = np.arange(N)
    window = 0.5 - 0.5 * np.cos(2 * np.pi * n_idx / N)
    freqs = np.arange(N) * SR / N
    low_band = (freqs > 0) & (freqs <= 1000)
    high_band = (freqs > 1000) & (freqs <= 4000)
    q_lo, q_hi = MIN_LAG, MAX_LAG           # 2.5 ms .. 13.3 ms (400 .. 75 Hz)
    fit_lo, fit_hi = 44, N // 2             # regression range for the cepstral baseline
    cpps, tilts = [], []
    for s in starts:
        seg = x[s:s + N]
        if len(seg) < N:
            continue
        X = np.fft.fft(seg * window)
        P = X.real ** 2 + X.imag ** 2
        L = 10 * np.log10(P + 1e-12)
        C = np.fft.fft(L).real / N
        q = np.arange(fit_lo, fit_hi + 1, dtype=float)
        cq = C[fit_lo:fit_hi + 1]
        qm, cm = q.mean(), cq.mean()
        slope = np.sum((q - qm) * (cq - cm)) / np.sum((q - qm) ** 2)
        peak_q = q_lo + int(np.argmax(C[q_lo:q_hi + 1]))
        line = cm + slope * (peak_q - qm)
        cpps.append(C[peak_q] - line)
        lp, hp = P[low_band].sum(), P[high_band].sum()
        tilts.append(10 * np.log10((lp + 1e-12) / (hp + 1e-12)))
    if not cpps:
        return 0.0, 0.0
    return float(np.mean(cpps)), float(np.mean(tilts))


def extract(x, return_frames=False):
    """Returns a dict of the 10 features, or None if the vowel is unusable."""
    x = np.asarray(x, dtype=np.float64)
    # Level normalization: scale so the loud part of the vowel (95th percentile frame)
    # sits at -20 dBFS. This removes differences in microphone distance and gain.
    db0 = frame_rms_db(x)
    # Near-silence is not a voice: refuse it rather than amplifying background hiss.
    if percentile(db0, 95) <= MIN_LOUD_DB:
        return None
    gain = 10 ** ((-20.0 - percentile(db0, 95)) / 20.0)
    x = x * gain
    db = frame_rms_db(x)
    floor = min(percentile(db, 10), -50.0)
    mask = voiced_mask(db, floor)

    best_start = best_len = run_start = run_len = 0
    for i, v in enumerate(mask):
        if v:
            if run_len == 0:
                run_start = i
            run_len += 1
            if run_len > best_len:
                best_len, best_start = run_len, run_start
        else:
            run_len = 0
    if best_len < 30:  # under ~0.3 s of voice
        return None

    trim = best_len // 10
    first = best_start + trim
    last = best_start + best_len - trim - 1
    available = last - first + 1
    if available > MAX_FRAMES:
        first = first + (available - MAX_FRAMES) // 2
        last = first + MAX_FRAMES - 1

    f0s, aps, amps, dbs, kept_idx = [], [], [], [], []
    analyzed = 0
    for i in range(first, last + 1):
        s = i * HOP
        e = s + PITCH_FRAME
        if e > len(x):
            break
        analyzed += 1
        frame = x[s:e]
        f0, ap = yin(frame)
        if f0 is not None:
            f0s.append(f0)
            aps.append(ap)
            amps.append(np.max(np.abs(frame)))
            dbs.append(to_db(np.sqrt(np.mean(frame ** 2))))
            kept_idx.append(i)
    if len(f0s) < 10:
        return None

    f0s = np.array(f0s)
    med = np.median(f0s)
    keep = np.abs(f0s - med) / med <= 0.2
    f0k = f0s[keep]
    apk = np.array(aps)[keep]
    ampk = np.array(amps)[keep]
    dbk = np.array(dbs)[keep]
    idxk = np.array(kept_idx)[keep]
    if len(f0k) < 10:
        return None

    mean_f0 = f0k.mean()
    semis = 12 * np.log2(f0k / mean_f0)
    periods = 1 / f0k

    feats = {
        "f0StdSemi": float(np.std(semis, ddof=1)),
        "jitter": float(np.mean(np.abs(np.diff(periods))) / periods.mean() * 100),
        "shimmer": float(np.mean(np.abs(np.diff(ampk))) / ampk.mean() * 100),
        "aperiodicity": float(apk.mean()),
        "voicedRatio": float(len(f0k) / analyzed),
        "f0Tremor": band_ratio(semis, 100.0),
        "ampTremor": band_ratio(dbk, 100.0),
        "ampStdDb": float(np.std(dbk, ddof=1)),
    }

    K = len(idxk)
    m = min(CPP_FRAMES, K)
    if m > 1:
        sel = [idxk[(j * (K - 1)) // (m - 1)] for j in range(m)]
    else:
        sel = [idxk[0]]
    cpp, tilt = cpp_and_tilt(x, [int(i) * HOP for i in sel])
    feats["cpp"] = cpp
    feats["spectralTilt"] = tilt
    if return_frames:
        return feats, x, [int(i) * HOP for i in sel]
    return feats


def vector(feats):
    return np.array([feats[n] for n in FEATURE_NAMES])
