# AI Speech Change Score: model report

**What the score means (shown in the app, PLAN.pdf Section 21):**
"How much this recording resembles voice recordings from people with ALS in a research dataset.
It is not a diagnosis and is most useful as a trend over time."

## Data

- **Minsk2020 ALS database** (Vashkevich & Rushkevich, 2021; GPL-3.0):
  https://github.com/Mak-Sim/Minsk2020_ALS_database
- 64 speakers (31 with ALS, 33 healthy controls). Each person held "ahh" (/a/) and "eee" (/i/).
  Recorded on different smartphones at 44.1 kHz (a few files at 48 kHz, resampled to 44.1 kHz).
- The data is not in this repository. To reproduce, clone it into `Scripts/ml/` (it is git-ignored).
- ALS and healthy speakers reuse 3 ID numbers, so speakers are keyed as `label * 1000 + id`.

## Features (all computed on the iPhone in Swift, identical to the Python code)

From the held "ahh" (`features.py` / `VoiceFeatures.swift`), after level normalization:

| Feature | Meaning |
|---|---|
| f0StdSemi | pitch variation (semitones) |
| jitter | cycle-to-cycle pitch change (%) |
| shimmer | cycle-to-cycle loudness change (%) |
| aperiodicity | YIN dip; 0 = perfectly periodic |
| voicedRatio | share of frames with a clear pitch |
| f0Tremor, ampTremor | share of pitch / loudness wobble at 3–12 Hz |
| ampStdDb | loudness steadiness |
| cpp | cepstral peak prominence (voice clarity) |
| spectralTilt | low vs high frequency energy |

From both vowels (`formants.py` / `FormantTracker.swift`): F1 and F2 of "ahh" and "eee" from an
order-12 LPC envelope (peaks narrower than 500 Hz), plus F2 ratio (eee / ahh) and vowel space
(distance between the two vowels in the F1–F2 plane). These describe tongue and jaw movement,
which bulbar ALS reduces.

Parity: unit tests check that Swift and Python give the same features on fixed test signals
(`VoiceFeaturesTests`, `FormantTrackerTests`) and the same model output on three real speakers
(`SpeechChangeModelTests`).

## How it was evaluated (honest, speaker-independent)

- **Nested leave-one-speaker-out cross-validation.** For each of the 64 people, the model is trained
  and tuned without any recording from that person, then scores that person. All numbers below come
  only from these held-out predictions.
- Hyperparameters (and, for the final model, how many features to keep) are chosen inside each
  training fold by 5-fold grid search on AUC.
- 95% confidence intervals: 2,000 bootstrap resamples of the held-out predictions.

## Results

| Model | Inputs | AUC (95% CI) | Accuracy | Sensitivity | Specificity |
|---|---|---|---|---|---|
| **Shipped:** LDA + in-fold feature selection | "ahh" features + formants of both vowels | **0.80 (0.67–0.90)** | **73.4%** | 64.5% | 81.8% |
| LDA (shrinkage) | "ahh" features only | 0.71 (0.58–0.83) | 67.2% | 54.8% | 78.8% |
| Random forest | "ahh" features only | 0.71 (0.57–0.83) | 68.8% | 67.7% | 69.7% |
| Logistic regression, SVM, gradient boosting, k-NN | "ahh" features only | 0.66–0.69 | 59–66% | | |
| Researchers' own 131 expert features, same evaluation | both vowels + formants | 0.80 | 71.9% | | |
| Age alone (confound check) | age | 0.65 | | | |

What we learned:
- Simple, regularized models beat complex ones (random forest, boosting, SVM). With 64 people,
  complex models memorize instead of generalizing.
- MFCC features (common in speech AI) did **not** help on held-out speakers (`exp_features.py`).
- The "eee" vowel's second formant (tongue reach) was the biggest gain: healthy 2.39 kHz vs
  ALS 2.08 kHz on average. The model's largest negative weights are F2 of "eee" and vowel space.
- Our phone-computable features match the researchers' full expert feature set (0.80 vs 0.80)
  under the same strict evaluation.
- A hand-picked 7-feature set scored 0.81, but those features were chosen after looking at all the
  data, so that number is optimistic and was not used.

Age check: in this dataset the ALS group is older on average, so age alone gives AUC 0.65. Among
healthy speakers the model's score is not related to age (Spearman 0.07), and adding the model to age
raises AUC from 0.63 to 0.75, so the model is not simply detecting older voices.

## Limitations (please read)

- 64 people is small. The confidence interval is wide (0.67–0.90).
- One recording session per person, in Belarus, Russian speakers, mixed phones. A different phone,
  room or language can shift the features. This is why the app shows the score as a **trend against
  the person's own baseline**, not as a one-time answer.
- Not validated for diagnosis, staging or any medical decision.
- The plan suggested training on VOC-ALS (Synapse); it needs an account and approval, so the openly
  licensed Minsk2020 set was used instead.

## Reproduce

```
cd Scripts/ml
git clone https://github.com/Mak-Sim/Minsk2020_ALS_database
python3 extract_all.py          # voice features   -> features_minsk.csv
python3 extract_formants.py     # formants          -> features_formants.csv
python3 train.py                # single-vowel model comparison (results/train_log.txt)
python3 exp_speaker.py          # two-vowel comparison          (results/exp_speaker_log.txt)
python3 exp_select.py           # shipped model's evaluation    (results/exp_select_log.txt)
python3 export_speaker_model.py "LDA+select" "a10+formants"   # -> SpeechChangeModelWeights.swift
```
Requires Python 3 with numpy, scipy, pandas, scikit-learn, openpyxl.

## Citation

Vashkevich M., Rushkevich Yu. Classification of ALS patients based on acoustic analysis of sustained
vowel phonations. Biomedical Signal Processing and Control, 2021, 65, 102350.
https://doi.org/10.1016/j.bspc.2020.102350
