import glob
import pandas as pd
from multiprocessing import Pool
from extract_all import load
from features import extract
from formants import formants
def work(path):
    r = extract(load(path), return_frames=True)
    if r is None: return dict(path=path)
    _, x, starts = r
    F1, F2 = formants(x, starts)
    return dict(path=path, F1=F1, F2=F2)
if __name__ == "__main__":
    with Pool(2) as p:
        rows = p.map(work, sorted(glob.glob("Minsk2020_ALS_database/*/*.wav")))
    d = pd.DataFrame(rows); d.to_csv("features_formants.csv", index=False)
    m = d.merge(pd.read_csv("features_minsk.csv")[["path","vowel","label"]], on="path")
    print(m.groupby(["vowel","label"])[["F1","F2"]].agg(["mean","std","count"]).round(3))
