# Resonance

**An iPhone companion for people living with ALS.** Resonance helps people keep talking in their own voice,
hands-free when they need to; keeps family close with alerts and messages; and measures speech, breathing and
movement at home so the care team gets a clear picture between visits.

Built for the 2026 Congressional App Challenge (California's 10th District).

Resonance never diagnoses. Every measurement is compared with the person's own baseline, and all data stays on
the iPhone.

---

## Features

### Communicate

- **Talk board.** Speak instantly with phrase tiles grouped by Needs, Feelings, People, Replies and the person's
  own phrases. A row of quick buttons (Yes, No, Pain, Wait, Feel) is always on screen.
- **Pain and feelings in one sentence.** *Pain* asks where it hurts and how bad it is, then says one clear
  sentence ("My chest hurts. It's a 6 out of 10, bad."). *Feel* offers nine faces with "a little" or "very".
- **Keyboard with word prediction** for anything not on a tile. Typed text can be spoken, saved as a phrase, or
  saved as a question for the care team.
- **The last message stays on screen,** so it can be repeated, shown in big letters to someone across the room,
  or sent to family as a text.
- **Hands-free control.** Everything works by touch, by head pointer (the Face ID camera follows the head and a
  button is chosen by holding still), or by switch scanning (a tap anywhere, a Bluetooth switch, or a long blink).
- **Voice Bank.** A recording studio walks through every phrase one at a time, so the Talk board plays the
  person's own recorded voice. Apple Personal Voice is supported, and **Back up my voice** saves every recording
  in one file to Files, iCloud Drive or a family member's phone.
- **Low-battery warning.** At 20% (and more strongly at 10%) the Talk board shows a warning with one button that
  asks people nearby to plug the phone in, because a flat battery means losing a voice.

### Stay safe

- **Alert.** One tap, or keeping the eyes closed for a few seconds (optional), starts a loud spoken call for
  help, a siren and a flashing screen and flashlight, with large buttons to call or text family. With a
  one-time Apple Shortcuts setup, the alert also texts family with no tap at all. It does not contact emergency
  services.
- **Breathing safety.** When daily answers show a breathing change, the app always shows the care-team safety
  message.

### Family and care

- **Family tab.** One-tap call and text, "Ask for help now", quick updates ("I'm okay", "Please come when you
  can"), a daily summary written for family, feelings shared this week, and a log of every alert and message.
  Family receive ordinary texts, so they don't need the app.
- **Care schedule.** Daily reminders for medicines, turning, water, mouth care and breathing equipment. Each
  reminder has **Done** (recorded in the family activity log) and **Remind me in 10 min** buttons.
- **Questions for my care team.** Questions can be written down whenever they come up, read aloud at the visit
  and ticked off. Open questions print on the Care Report.

### Measure and track

- **Weekly check-in.** A guided six-minute session: Voice, Breath, Motor and daily questions, ending with a
  summary of the week. Each test can also be done on its own.
  - **Voice Lab:** held "ahh" and "eee", "pa-ta-ka", and reading a passage aloud.
  - **Breath test:** counting out loud on one breath.
  - **Motor Lab:** finger tapping with each hand, spiral tracing and a steadiness hold.
  - **Daily Function Check:** eight questions about everyday function, plus mood.
- **Explained results.** Every test starts with why it matters in ALS and ends with what each result means in
  plain words, compared with the person's own baseline, plus next steps that link to the feature that helps.
- **Trends.** Every measurement over time with the personal baseline and normal range, a flag only when a change
  is larger than the person's usual variation, and the Function Index (0–100).
- **Care Report.** A one-page PDF summary to share with the care team.

## The AI Speech Change Score

A machine-learning model that runs entirely on the phone, trained on research recordings from people with ALS
and healthy speakers (the Minsk2020 database).

- **Inputs:** 10 voice-quality features from the held "ahh" (pitch and loudness steadiness, voice clarity,
  tremor) and vowel formants from "ahh" and "eee", which reflect tongue and jaw movement.
- **Evaluation:** nested leave-one-speaker-out cross-validation, so every speaker is scored by a model that never
  heard them. AUC 0.80 (95% CI 0.67–0.90), 73% accuracy and 82% specificity, which matches the dataset authors'
  own 131-feature set under the same test.
- **Shown to the user as:** *"How much this recording resembles voice recordings from people with ALS in a
  research dataset. It is not a diagnosis and is most useful as a trend over time."*

Methods, every model tried, limitations and reproduction steps are in
[`Scripts/ml/MODEL_REPORT.md`](Scripts/ml/MODEL_REPORT.md).

## How each measurement works

| Measurement | Method |
|---|---|
| Max phonation time | Longest voiced run of the held "ahh" (frame energy 15 dB above the room's noise floor) |
| Pitch, pitch variation, jitter, shimmer | YIN pitch tracking on 40 ms frames with octave-error rejection |
| Voice clarity (CPP) | Cepstral peak prominence over 20 frames |
| Tongue reach and vowel space | LPC formant tracking (order 12, Levinson-Durbin) on "ahh" and "eee" |
| Pa-ta-ka rate and rhythm | Syllable peaks in the loudness envelope (6 dB prominence, 70 ms spacing) |
| Speaking rate, word clarity, pauses | On-device speech recognition aligned word by word to the known passage |
| Count on one breath | On-device speech recognition reads the numbers; the longest rising run is the count |
| Tap speed, accuracy, rhythm | Touch timestamps on two targets, for each hand |
| Spiral accuracy, speed, tremor | Finger path compared with an Archimedean spiral |
| Hold steadiness and tremor | 100 Hz accelerometer: RMS, 3–12 Hz power share, first versus last window |
| Function Index | Each measure scored against the baseline (median of the first 3 check-ins); speech 40%, motor 35%, daily function 25% |
| "Noticeable change" flag | The last two check-ins are both outside the normal range (2× the person's own variation) and the trend projects more than a 10% change over 4 weeks |

## Privacy and safety

- No network calls, no accounts and no analytics. Camera frames are never saved.
- Speech recognition runs on the device; the app asks before ever using Apple's servers.
- Texts and calls go through the iPhone's own Messages and Phone apps.
- Not a medical device: Resonance does not diagnose ALS or any other condition and does not replace a care team.

## Build and run

1. Open `Resonance.xcodeproj` in Xcode 16 or newer.
2. Select the **Resonance** target, open **Signing & Capabilities**, and choose your team.
3. Run on an iPhone with iOS 18.2 or later. The microphone, motion sensors and face tracking need a real
   device; everything else works in the Simulator (choose "I'm just exploring" to load demo data).
4. Run the tests with **Product → Test** (⌘U). The 157 unit tests cover the signal processing, voice and motor
   analysis, the AI model (checked against the Python reference), insights and next steps, hands-free input,
   and the communication and care features.

## Technology

Swift and SwiftUI with Apple frameworks only: SwiftData, AVFoundation, Speech, Accelerate, CoreMotion, ARKit,
Swift Charts, UserNotifications, App Intents, MessageUI and ContactsUI. The model was trained in Python (NumPy,
SciPy, pandas, scikit-learn) and its weights are exported to Swift.

```
Resonance/App        design system, Siri and Shortcuts actions
Resonance/Models     data models and metric definitions
Resonance/Services   audio, speech, motor, insights, ML, hands-free input, output, family, reminders, report
Resonance/Features   one folder per screen
ResonanceTests       unit tests
Scripts/ml           model training, evaluation and MODEL_REPORT.md
```

## Limitations

- Phone measurements are estimates. Noise, posture, distance and how the person feels that day all affect them,
  so check-ins work best in the same room and position each week.
- The AI model was trained on 64 people from one research dataset; see the model report for details.

## Credits

- Minsk2020 ALS database: Vashkevich & Rushkevich (2021), *Biomedical Signal Processing and Control* 65:102350.
  The data is not redistributed in this repository.
- YIN pitch estimation: de Cheveigné & Kawahara (2002).

## AI-use disclosure

Resonance was built with help from Claude, an AI assistant by Anthropic. How the work was divided is described
in [`AI_USE.md`](AI_USE.md).
