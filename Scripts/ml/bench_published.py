"""Benchmark: the paper's own 131 features under the SAME honest nested leave-one-speaker-out CV."""
import warnings; warnings.filterwarnings("ignore")
import numpy as np, pandas as pd
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GridSearchCV, LeaveOneOut, StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
d = pd.read_csv("Minsk2020_ALS_database/Minsk2020_ALS_dataset.csv")
y = d["Diagnosis (ALS)"].values
cols_all = [c for c in d.columns if c not in ("ID", "Sex", "Age", "Diagnosis (ALS)")]
cols_a = [c for c in cols_all if c.endswith("_a") or "a_{" in c or c.startswith("Ha(") or c.startswith("CCa") or c.startswith("dCCa")]
sets = {"paper /a/ only": cols_a, "paper all (a+i+formants)": cols_all,
        "paper F2_i,F2_conv,d_1": ["F2_i", "F2_{conv}", "d_1"]}
for name, cols in sets.items():
    X = d[cols].values.astype(float)
    for mname, model, grid in [("LDA", LinearDiscriminantAnalysis(solver="lsqr"), {"clf__shrinkage": [0.2, 0.5, 0.8, "auto"]}),
                               ("LR", LogisticRegression(max_iter=5000), {"clf__C": [0.01, 0.03, 0.1, 0.3, 1]})]:
        p = np.zeros(len(y))
        for tr, te in LeaveOneOut().split(X):
            gs = GridSearchCV(Pipeline([("s", StandardScaler()), ("clf", model)]), grid, scoring="roc_auc",
                              cv=StratifiedKFold(5, shuffle=True, random_state=7))
            gs.fit(X[tr], y[tr]); p[te] = gs.predict_proba(X[te])[:, 1]
        print(f"{name:28s} {mname}: auc={roc_auc_score(y, p):.3f} acc={((p >= .5) == y).mean():.3f}", flush=True)
