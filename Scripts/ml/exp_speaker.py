"""Speaker-level model: one row per person combining the "ahh" and "eee" recordings.
Honest nested leave-one-speaker-out CV, inner 5-fold grid search on AUC."""
import warnings; warnings.filterwarnings("ignore")
import json, sys
import numpy as np, pandas as pd
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.svm import SVC
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GridSearchCV, LeaveOneOut, StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from features import FEATURE_NAMES

f = pd.read_csv("features_minsk.csv").merge(pd.read_csv("features_formants.csv"), on="path")  # speaker = label*1000 + id
a = f[f.vowel == "a"].set_index("speaker"); i = f[f.vowel == "i"].set_index("speaker")
spk = sorted(set(a.index) & set(i.index))
d = pd.DataFrame(index=spk)
for c in FEATURE_NAMES + ["F1", "F2"]:
    d[c + "_a"] = a.loc[spk, c]; d[c + "_i"] = i.loc[spk, c]
d["F2ratio"] = d.F2_i / d.F2_a          # how far the tongue moves between "ahh" and "eee"
d["vowelSpace"] = np.hypot(d.F1_a - d.F1_i, d.F2_a - d.F2_i)
d["label"] = a.loc[spk, "label"]; d["Age"] = a.loc[spk, "Age"]
d = d.dropna(subset=[c + "_a" for c in FEATURE_NAMES] + [c + "_i" for c in FEATURE_NAMES])
d.to_csv("speaker_table.csv")
y = d.label.values
A10 = [c + "_a" for c in FEATURE_NAMES]; I10 = [c + "_i" for c in FEATURE_NAMES]
FORM = ["F1_a", "F2_a", "F1_i", "F2_i", "F2ratio", "vowelSpace"]
SETS = {"a10": A10, "a10+i10": A10 + I10, "formants": FORM, "a10+formants": A10 + FORM,
        "a10+i10+formants": A10 + I10 + FORM, "F2_i+vowelSpace+5best": ["F2_i", "vowelSpace", "F2ratio", "voicedRatio_a", "f0StdSemi_a", "jitter_a", "cpp_a"]}
MODELS = {"LDA": (LinearDiscriminantAnalysis(solver="lsqr"), {"clf__shrinkage": [0.2, 0.5, 0.8, "auto"]}),
          "LR": (LogisticRegression(max_iter=5000), {"clf__C": [0.01, 0.03, 0.1, 0.3, 1]}),
          "SVM": (SVC(), {"clf__C": [0.3, 1, 3], "clf__gamma": ["scale", 0.03, 0.1]}),
          }
out = {}
for sname, cols in SETS.items():
    X = d[cols].values.astype(float)
    for mname, (m, g) in MODELS.items():
        p = np.zeros(len(y))
        for tr, te in LeaveOneOut().split(X):
            gs = GridSearchCV(Pipeline([("imp", SimpleImputer(strategy="median")), ("s", StandardScaler()), ("clf", m)]), g, scoring="roc_auc",
                              cv=StratifiedKFold(5, shuffle=True, random_state=7), n_jobs=2)
            gs.fit(X[tr], y[tr])
            p[te] = gs.predict_proba(X[te])[:, 1] if hasattr(gs.best_estimator_, "predict_proba") \
                else 1 / (1 + np.exp(-gs.decision_function(X[te])))
        auc = roc_auc_score(y, p); acc = ((p >= .5) == y).mean()
        out[f"{sname}|{mname}"] = dict(auc=auc, acc=acc, probs=p.tolist())
        print(f"{sname:24s} {mname:4s} auc={auc:.3f} acc={acc:.3f}", flush=True)
json.dump(dict(results=out, labels=y.tolist(), speakers=list(map(int, d.index))), open("speaker_results.json", "w"))
print("n speakers:", len(y), "age-only AUC:", round(roc_auc_score(y, d.Age), 3))
