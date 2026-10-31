# Context

## Domain
- A transcript is the editable text recognized or typed by the user.
- An expression is a restricted arithmetic string parsed by the local parser.
- A calculation stores the reviewed expression, numeric result, and creation time.
- A calculation is added to history only after successful evaluation.
- Decimal style is a user preference; mixed separator styles are rejected.

## Data
- Browser local storage is the record of the user's history and settings.
- The local HTTP server serves static files and has no application database.
- No sample or customer data is bundled.

## Native mode
Voice Calc Studio is a macOS menu bar calculator, with the browser calculator retained for typed entry and editable transcripts or expressions. Browser speech privacy depends on the browser provider. Native speech requires on-device recognition and has no network fallback.

The native app uses bounded hold-to-capture, exact physical modifier state, finite-result validation, and clipboard copy after calculation. The shortcut defaults to Right Command and can be changed to Right Option or Left Option. Settings can request Accessibility, Microphone, and Speech Recognition access before capture. Its bundle identifier is `com.gmperkinsmba.voicecalcstudio.native`; the browser server remains on loopback port 8341.

Native builds belong in `native/dist/` and install as `Voice Calc Studio.app`. Tests for native core logic must not launch the app or request microphone access.
