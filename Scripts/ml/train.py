"""
Train and evaluate the Resonance voice model.

Honest evaluation: nested cross-validation grouped by SPEAKER.
- Outer loop: leave one speaker out (64 folds). The held-out person's recording is never
  seen during training or tuning.
- Inner loop: 5-fold grouped CV picks each model's settings (hyperparameters) using AUC.
Reported numbers come only from the outer, held-out predictions.
"""
import json, warnings
import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GridSearchCV, LeaveOneGroupOut, StratifiedGroupKFold
from sklearn.neighbors import KNeighborsClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from features import FEATURE_NAMES

warnings.filterwarnings("ignore")
RNG = 7

df = pd.read_csv("features_minsk.csv")
df = df[df.ok].reset_index(drop=True)

MODELS = {
    "Logistic regression": (LogisticRegression(max_iter=5000),
                            {"clf__C": [0.03, 0.1, 0.3, 1, 3, 10]}),
    "LDA (shrinkage)": (LinearDiscriminantAnalysis(solver="lsqr"),
                        {"clf__shrinkage": [0.0, 0.2, 0.5, 0.8, "auto"]}),
    "SVM (RBF)": (SVC(random_state=RNG),
                  {"clf__C": [0.3, 1, 3, 10], "clf__gamma": ["scale", 0.03, 0.1, 0.3]}),
    "Random forest": (RandomForestClassifier(n_estimators=200, random_state=RNG, n_jobs=1),
                      {"clf__max_depth": [2, 3, 5, None], "clf__min_samples_leaf": [1, 3, 5]}),
    "Gradient boosting": (GradientBoostingClassifier(random_state=RNG),
                          {"clf__n_estimators": [100], "clf__max_depth": [1, 2, 3],
                           "clf__learning_rate": [0.05, 0.1], "clf__subsample": [0.8]}),
    "k-nearest neighbors": (KNeighborsClassifier(),
                            {"clf__n_neighbors": [3, 5, 7, 9, 11], "clf__weights": ["uniform", "distance"]}),
}


def nested_cv(model, grid, train_vowels):
    """Outer leave-one-speaker-out on /a/ recordings; train on the chosen vowels of the other speakers."""
    test_df = df[df.vowel == "a"].reset_index(drop=True)
    probs = np.zeros(len(test_df))
    for i, row in test_df.iterrows():
        tr = df[(df.speaker != row.speaker) & (df.vowel.isin(train_vowels))]
        X, y, g = tr[FEATURE_NAMES].values, tr.label.values, tr.speaker.values
        pipe = Pipeline([("scale", StandardScaler()), ("clf", clone(model))])
        inner = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=RNG)
        search = GridSearchCV(pipe, grid, scoring="roc_auc", cv=inner, n_jobs=2)
        search.fit(X, y, groups=g)
        xq = row[FEATURE_NAMES].values.reshape(1, -1).astype(float)
        if hasattr(search.best_estimator_, "predict_proba"):
            probs[i] = search.predict_proba(xq)[0, 1]
        else:  # SVM: squash the decision value so 0.5 is the decision boundary
            probs[i] = 1 / (1 + np.exp(-search.decision_function(xq)[0]))
    return test_df.label.values, probs


def metrics(y, p, threshold=0.5):
    pred = (p >= threshold).astype(int)
    tp = int(((pred == 1) & (y == 1)).sum()); tn = int(((pred == 0) & (y == 0)).sum())
    fp = int(((pred == 1) & (y == 0)).sum()); fn = int(((pred == 0) & (y == 1)).sum())
    return dict(accuracy=(tp + tn) / len(y), sensitivity=tp / (tp + fn), specificity=tn / (tn + fp),
                auc=roc_auc_score(y, p), tp=tp, tn=tn, fp=fp, fn=fn)


def bootstrap_ci(y, p, n=2000):
    rng = np.random.default_rng(RNG)
    aucs, accs = [], []
    for _ in range(n):
        idx = rng.integers(0, len(y), len(y))
        if len(set(y[idx])) < 2:
            continue
        aucs.append(roc_auc_score(y[idx], p[idx]))
        accs.append(((p[idx] >= 0.5) == y[idx]).mean())
    return (np.percentile(aucs, [2.5, 97.5]).tolist(), np.percentile(accs, [2.5, 97.5]).tolist())


if __name__ == "__main__":
    import os, sys
    out = "results.jsonl"
    done = set()
    if os.path.exists(out):
        done = {(r["model"], r["training"]) for r in map(json.loads, open(out))}
    for train_vowels, tag in [(["a"], "/a/ only"), (["a", "i"], "/a/ + /i/")]:
        for name, (model, grid) in MODELS.items():
            if (name, tag) in done:
                continue
            y, p = nested_cv(model, grid, train_vowels)
            m = metrics(y, p)
            auc_ci, acc_ci = bootstrap_ci(y, p)
            rec = dict(model=name, training=tag, **m, auc_ci=auc_ci, acc_ci=acc_ci, probs=p.tolist())
            with open(out, "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(f"{tag:10s} {name:22s} acc={m['accuracy']:.3f} sens={m['sensitivity']:.3f} "
                  f"spec={m['specificity']:.3f} auc={m['auc']:.3f} auc95%={auc_ci[0]:.2f}-{auc_ci[1]:.2f}", flush=True)

    # Baseline for honesty: how well does AGE alone separate the groups?
    a = df[df.vowel == "a"]
    print(f"Age-only AUC (confound check): {roc_auc_score(a.label, a.Age):.3f}", flush=True)
