# AI-use disclosure

Resonance was built by Aarnev with help from Claude, an AI assistant made by Anthropic. The Congressional
App Challenge allows AI tools when their use is disclosed. This document explains how the work was divided:
what I did, what Claude wrote, and how that work was checked.

## Summary

| Area | Who |
|---|---|
| Problem choice, users, feature requirements and constraints | Aarnev |
| Product and design decisions; review and acceptance of changes | Aarnev |
| Swift code, unit tests and the machine-learning scripts | Claude, directed by Aarnev |
| Project setup, version control, device testing, demo and submission | Aarnev |

The written specification (`PLAN.pdf`) and the instructions file for the assistant (`CLAUDE.md`) were drafted
with Claude from my requirements.

## My role

**Product definition**
- Chose the problem: everyday communication and care coordination for people living with ALS, designed for
  three groups of users: the person with ALS, the family members who help them, and their care team.
- Defined the five core features the app had to deliver: text-to-speech with quick phrases and typing, voice
  banking, hands-free control (head pointer or single switch), a one-tap or blink emergency alert, and a
  caregiver connection that works on family members' own phones.

**System constraints and design decisions**
- Set the privacy model: everything stays on the iPhone, with no accounts, no servers and no network calls.
  Family receive ordinary texts, so they never need to install anything.
- Set the platform rules: Apple frameworks only (no third-party packages), SwiftUI and SwiftData, and all
  signal processing and analysis kept in plain Swift types, separate from the UI, so each one can be unit tested.
- Set the accessibility requirements: 60-point minimum touch targets, a VoiceOver label on every control, and
  layouts that hold up at the largest text sizes and in Dark Mode.
- Set the safety wording rules: the app never diagnoses, the alert states that it does not contact emergency
  services, and the breathing safety message always appears when its rule triggers.
- Chose the hands-free alert design: the alert runs a one-time Apple Shortcuts automation that texts family
  with no tap needed, with a two-second window to cancel a mistaken alert before anything is sent.
- Asked for and accepted the features added during development: the care schedule, Questions for my care team,
  voice backup, the low-battery warning, and Done/snooze buttons on reminders.

**Development process and quality control**
- Set the development process: small tasks built one at a time, each required to compile without warnings and
  pass the full unit test suite before it was accepted (157 tests at submission).
- Asked for the finished work to be checked repeatedly. This led to six independent code-review rounds covering
  crash risks, audio interruptions, alert edge cases, report layout and accessibility; every finding was fixed
  and re-tested.
- Directed visual and wording changes during development, including colour, layout and simpler screens.

**Project setup and delivery**
- Created the Xcode project, configured signing and on-device deployment, managed version control, and
  prepared the demo video and the submission.

## What Claude wrote

**App structure and design system**
- `Resonance/ResonanceApp.swift` and `Resonance/ContentView.swift` (five tabs, launch and shortcut handling),
  `Resonance/App/AppTheme.swift` (colours, type, buttons, cards), `Resonance/App/AppIntents.swift` (Siri and
  Shortcuts actions), the app icon images and accent colour.
- The data models in `Resonance/Models/`.

**Talk board and hands-free control**
- `Resonance/Features/Talk/`: the Talk board (quick Yes/No/Pain/Wait/Feel row, phrase tiles, message strip,
  pain and feelings panels, battery banner), the keyboard with word prediction, the phrase library, head-pointer
  calibration, hands-free settings and the emergency alert screen.
- `Resonance/Services/Gaze/`: face tracking, head-pointer mapping, dwell selection, switch scanning and blink
  detection.
- `Resonance/Services/Talk/`: pain sentences and feelings.
- `Resonance/Services/Output/`: speech output, Voice Bank recording, voice backup, the alarm tone and battery
  monitoring.
- `Resonance/Features/VoiceBank/`: the recording studio, phrase recording and Personal Voice.

**Family and care tools**
- `Resonance/Features/Family/`: the Family tab, texts and calls, the care schedule, and Questions for my care team.
- `Resonance/Services/Family/` and `Resonance/Services/Reminders/`: family messages, the alert shortcut, care
  reminders and their notification buttons.

**Check-ins, measurement and insights**
- `Resonance/Features/`: `CheckIn`, `VoiceLab`, `Breath`, `MotorLab`, `FunctionCheck`, `Onboarding`, `Today`,
  `Trends`, `Profile` and `Shared`.
- `Resonance/Services/Audio/` (recording, signal processing, pitch, voice features, formants),
  `Resonance/Services/Speech/` (on-device transcription, reading and breath analysis),
  `Resonance/Services/Motor/` (tapping, spiral and steadiness analysis),
  `Resonance/Services/Insights/` (personal baseline, change detection, Function Index),
  `Resonance/Services/Plan/` (next steps and breathing safety), `Resonance/Services/Report/` (Care Report PDF)
  and `Resonance/Services/Demo/` (demo data).

**AI Speech Change Score**
- `Scripts/ml/`: Python scripts for feature extraction, training, nested cross-validation and export, plus
  `MODEL_REPORT.md`, which documents the model's performance and limitations.
- `Resonance/Services/ML/`: the on-device model and its exported weights.

**Tests and documentation**
- The unit tests in `ResonanceTests/`, and `README.md`.
