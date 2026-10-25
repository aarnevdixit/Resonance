"""Quick experiment: do MFCC/spectral features help on held-out speakers? (LR + LDA, nested LOSO)"""
import warnings; warnings.filterwarnings("ignore")
import numpy as np, pandas as pd
from sklearn.base import clone
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GridSearchCV, StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from features import FEATURE_NAMES
from features_extra import EXTRA_NAMES
df = pd.read_csv("features_minsk.csv").merge(pd.read_csv("features_extra.csv"), on="path")
MF = [f"mfcc{i}_mean" for i in range(1, 13)]
SETS = {"base10": FEATURE_NAMES, "base+mfccmean": FEATURE_NAMES + MF,
        "base+all": FEATURE_NAMES + EXTRA_NAMES, "mfcc only": MF + [f"mfcc{i}_std" for i in range(1, 13)]}
MODELS = {"LR": (LogisticRegression(max_iter=5000), {"clf__C": [0.01, 0.03, 0.1, 0.3, 1]}),
          "LDA": (LinearDiscriminantAnalysis(solver="lsqr"), {"clf__shrinkage": [0.2, 0.5, 0.8, "auto"]})}
def run(cols, model, grid, vowels, test_vowels=("a",)):
    spk = sorted(df.speaker.unique()); ys, ps = [], []
    for s in spk:
        tr = df[(df.speaker != s) & df.vowel.isin(vowels)]
        te = df[(df.speaker == s) & df.vowel.isin(test_vowels)]
        if te.empty: continue
        pipe = Pipeline([("s", StandardScaler()), ("clf", clone(model))])
        gs = GridSearchCV(pipe, grid, scoring="roc_auc", cv=StratifiedGroupKFold(5, shuffle=True, random_state=7))
        gs.fit(tr[cols].values, tr.label.values, groups=tr.speaker.values)
        ps.append(gs.predict_proba(te[cols].values)[:, 1].mean()); ys.append(te.label.iloc[0])
    ys, ps = np.array(ys), np.array(ps)
    return roc_auc_score(ys, ps), ((ps >= .5) == ys).mean()
for sname, cols in SETS.items():
    for mname, (m, g) in MODELS.items():
        for vw, tv, tag in [(["a"], ("a",), "a->a"), (["a", "i"], ("a",), "ai->a"), (["a", "i"], ("a", "i"), "ai->ai avg")]:
            auc, acc = run(cols, m, g, vw, tv)
            print(f"{sname:15s} {mname:4s} {tag:11s} auc={auc:.3f} acc={acc:.3f}", flush=True)
