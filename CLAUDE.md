# Resonance — instructions for Claude

Resonance is an iOS app for people living with ALS, built for the 2026 Congressional App Challenge
(California's 10th District). The full specification is `PLAN.pdf` in this folder. Read the
section a task points to before writing code.

## How we work
- Build the tasks in PLAN.pdf Section 16 in order (T01 to T24). One task at a time.
- Before coding, list the files you will create or change.
- Write complete, compilable files, not fragments.
- After writing code, compile with xcodebuild and fix every error and warning you introduced:
  `xcodebuild -scheme Resonance -destination 'generic/platform=iOS' build`
- Run unit tests on a simulator when the task has tests:
  `xcodebuild test -scheme Resonance -destination 'platform=iOS Simulator,name=iPhone 16'`
  (if that simulator name is not installed, list them with `xcrun simctl list devices available`
  and pick an available iPhone).
- Then tell me exactly how to test the task on my real iPhone, using the task's "Done when" list.
  Microphone, motion and face tracking only work on the device, so I will report back.
- When a task passes, suggest a git commit message. Do not push without asking.
- Keep a running list in `AI_USE.md` of the files and functions you wrote or substantially changed.
  I need it for the competition's AI-use disclosure.

## Technical rules
- iOS 17.0+, Swift, SwiftUI for all UI, SwiftData for storage, `@Observable` view models.
- Apple frameworks only: AVFoundation, AVFAudio, Speech, Accelerate, CoreMotion, ARKit, Charts,
  SwiftData, CoreML, SoundAnalysis, UserNotifications. No third-party packages.
- No network calls. All data stays on the device. Never save camera frames.
- If on-device speech recognition is unavailable, ask the user before using server recognition
  (PLAN.pdf Section 9).
- Put algorithms (DSP, pitch, syllable peaks, text alignment, tap analysis, insights, gaze mapping)
  in plain Swift types with no UI imports so they can be unit tested.
- Use the file layout in PLAN.pdf Section 7 and the data model in Section 8.
- Large text and tap targets of at least 60 pt; every control needs a VoiceOver label.
- Avoid force unwraps on sensor or file data; show a calm error instead of crashing.

## Wording rules
- Resonance never diagnoses. Use the exact wording in PLAN.pdf Section 21 for consent, change
  flags, the AI Speech Change Score and the emergency tile.
- The breathing safety message in Section 11 must always appear when its rule triggers.

## Datasets (stretch task T21 only)
- Research datasets live in `Datasets/`, which must be listed in `.gitignore`. Never commit them.
- Training code goes in `Scripts/` and runs on the Mac, not in the app.

## If something in the plan is wrong or out of date
Choose the simplest working option, leave a code comment explaining the change, and tell me.
