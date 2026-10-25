"""Feature selection done honestly: SelectKBest runs INSIDE each training fold, so the held-out
speaker never influences which features are chosen."""
import warnings; warnings.filterwarnings("ignore")
import json
import numpy as np, pandas as pd
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.feature_selection import SelectKBest, f_classif
from sklearn.impute import SimpleImputer
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GridSearchCV, LeaveOneOut, StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from features import FEATURE_NAMES
d = pd.read_csv("speaker_table.csv", index_col=0)
A10 = [c + "_a" for c in FEATURE_NAMES]; I10 = [c + "_i" for c in FEATURE_NAMES]
FORM = ["F1_a", "F2_a", "F1_i", "F2_i", "F2ratio", "vowelSpace"]
y = d.label.values
res = {}
for name, cols in {"a10+formants": A10 + FORM, "a10+i10+formants": A10 + I10 + FORM}.items():
    X = d[cols].values.astype(float)
    p = np.zeros(len(y)); chosen = []
    for tr, te in LeaveOneOut().split(X):
        pipe = Pipeline([("imp", SimpleImputer(strategy="median")), ("s", StandardScaler()),
                         ("sel", SelectKBest(f_classif)), ("clf", LinearDiscriminantAnalysis(solver="lsqr"))])
        grid = {"sel__k": [4, 6, 8, 10, 12, len(cols)], "clf__shrinkage": [0.2, 0.5, 0.8, "auto"]}
        gs = GridSearchCV(pipe, grid, scoring="roc_auc", cv=StratifiedKFold(5, shuffle=True, random_state=7), n_jobs=2)
        gs.fit(X[tr], y[tr]); p[te] = gs.predict_proba(X[te])[:, 1]
        chosen.append(gs.best_params_["sel__k"])
    auc = roc_auc_score(y, p); acc = ((p >= .5) == y).mean()
    rng = np.random.default_rng(7); boots = []
    for _ in range(2000):
        idx = rng.integers(0, len(y), len(y))
        if len(set(y[idx])) == 2: boots.append(roc_auc_score(y[idx], p[idx]))
    lo, hi = np.percentile(boots, [2.5, 97.5])
    tp = ((p >= .5) & (y == 1)).sum(); tn = ((p < .5) & (y == 0)).sum()
    res[name] = dict(auc=auc, acc=acc, sens=tp / (y == 1).sum(), spec=tn / (y == 0).sum(), ci=[lo, hi],
                     k_median=float(np.median(chosen)), probs=p.tolist())
    print(f"{name:20s} LDA+select auc={auc:.3f} (95% CI {lo:.2f}-{hi:.2f}) acc={acc:.3f} "
          f"sens={res[name]['sens']:.3f} spec={res[name]['spec']:.3f} median k={np.median(chosen)}", flush=True)
json.dump(res, open("select_results.json", "w"))
