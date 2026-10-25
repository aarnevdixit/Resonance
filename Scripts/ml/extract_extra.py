import glob, os
import pandas as pd
from extract_all import load
from features import extract
from features_extra import extra, EXTRA_NAMES
rows = []
for path in sorted(glob.glob("Minsk2020_ALS_database/*/*.wav")):
    name = os.path.basename(path)
    r = extract(load(path), return_frames=True)
    if r is None:
        continue
    _, x, starts = r
    rows.append(dict(path=path, **extra(x, starts)))
pd.DataFrame(rows).to_csv("features_extra.csv", index=False)
print(len(rows))
