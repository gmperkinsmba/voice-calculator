# Security

Voice Calculator parses spoken or typed expressions locally. The native speech path requires on-device speech support and macOS permissions. Browser speech is disclosed separately in the browser version. The app does not send calculation history to a cloud service. Microphone access and live voice behavior depend on macOS permissions. Use made-up expressions in reports, not private recordings.

The native app has an ad-hoc code signature. This lets the installer check whether its files changed. It does not prove who made the app. The build is not notarized. Local files, where used, are plaintext and follow account permissions. Use your Mac’s disk encryption to protect saved files.

Report security issues through [GitHub private vulnerability reporting](https://github.com/gmperkinsmba/voice-calculator/security/advisories/new).
