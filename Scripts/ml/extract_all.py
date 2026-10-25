import glob, os, json, sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly
from multiprocessing import Pool
import pandas as pd
from features import extract, FEATURE_NAMES, SR

ROOT = "Minsk2020_ALS_database"

def load(path):
    sr, x = wavfile.read(path)
    x = x.astype(np.float64) / 32768.0
    if sr == 48000:
        x = resample_poly(x, 147, 160)
    elif sr != SR:
        raise ValueError(sr)
    return x

def work(path):
    name = os.path.basename(path)
    sid = int(name.split("_")[0])
    vowel = name.split("_")[1][0]
    label = 1 if "/ALS/" in path else 0
    f = extract(load(path))
    return dict(path=path, speaker=sid, vowel=vowel, label=label, **(f or {}), ok=f is not None)

if __name__ == "__main__":
    files = sorted(glob.glob(f"{ROOT}/*/*.wav"))
    with Pool(2) as p:
        rows = p.map(work, files)
    df = pd.DataFrame(rows)
    als = pd.read_excel(f"{ROOT}/ALS_table.xlsx").rename(columns={"Subject code": "speaker"})
    hc = pd.read_excel(f"{ROOT}/HC_table.xlsx").rename(columns={"Subject code": "speaker"})
    meta = pd.concat([als.assign(label=1), hc.assign(label=0)])[["speaker", "label", "Age", "Sex"]]
    df = df.merge(meta, on=["speaker", "label"], how="left")
    # ALS and healthy speakers reuse ID numbers (3 overlap), so make IDs unique per group.
    df["speaker"] = df.label * 1000 + df.speaker
    df.to_csv("features_minsk.csv", index=False)
    print(df.groupby(["vowel", "label"]).ok.agg(["sum", "count"]))
    print(df[df.vowel == "a"].groupby("label")[FEATURE_NAMES].mean().T.round(3))
