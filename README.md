# Voice Calculator

**First principle:** Show the math the person meant. Show the answer before they copy it.

Voice Calculator is a macOS menu bar calculator. Hold a modifier key to speak a calculation, then review the expression and copied answer in a floating panel. The browser app remains available for typed entry and editable transcripts or expressions. Browser speech uses the browser's provider and may send audio online. Native speech requires on-device English recognition and never falls back to a network service.

## Install and run on macOS

The separate native app lives under `native/`. It does not replace or modify the browser app. It requires macOS 13 or later.

```sh
native/build.sh
native/install.sh
```

The app appears in the menu bar as **Voice Calculator**. Hold Right Command to capture. Settings also offers Right Option and Left Option. The shortcut applies to the exact physical key, so holding another modifier does not keep capture active after release.

Before capture, choose **Request access** in Settings. Allow these permissions:

- Microphone
- Speech Recognition
- Accessibility

On first use, macOS may ask for microphone and speech access. Settings shows each permission. Recognition runs in English on your Mac. If your Mac cannot recognize speech on-device, capture stops. Audio is not sent elsewhere. Capture ends when you release the key or after 30 seconds. The app shows the recognized expression and answer in a small floating panel. It copies only a finite answer and has a Close control.

Build output is written to `native/dist/Voice Calculator.app`. The installer targets `~/Applications/Voice Calculator.app`. It refuses an existing destination unless you pass `--replace-voice-calculator`, and then replaces only an app with this native bundle identifier. It never targets the browser app.

The build is ad-hoc signed for local use and is not notarized or Developer ID signed. macOS may require local security approval, and privacy permissions can need renewal after rebuilding.

## Browser mode (optional)

Python 3.10 or later is required.

```sh
python3 server.py
```

Open <http://127.0.0.1:8341>. The server binds to loopback only. Stop it with Ctrl+C.

## Use

Enter an expression such as `12 percent of 80` or `2 plus 3 times 4`, then press Enter. Choose **Hold to speak**, then release to stop. Review or edit the transcript and expression before copying. Use Settings to choose decimal style and clear local history.

You can say plus, minus, times, divided by, percent of, parentheses, or digits. The app rejects unclear decimal phrases. Correct them before you continue. Results have no units. Currency and measurement units show a clear error. Unit conversion and general conversation are not supported. History stays in this browser on this device.

## Test

```sh
node tests/test_calc.js && python3 -m unittest discover -s tests -v
```

Native core tests compile without opening the menu bar app or accessing the microphone:

```sh
swiftc -parse-as-library native/Sources/MathParser.swift native/Sources/VoiceCalcCore.swift native/Tests/main.swift -o /tmp/voice-calc-native-tests
/tmp/voice-calc-native-tests
```

After building, `native/dist/Voice Calculator.app/Contents/MacOS/VoiceCalcStudio --self-test` checks calculation, menu targets, Settings access controls, and status-copy behavior. It does not enter the app launch lifecycle, install the global listener, request permissions, or start a microphone session.

## Data

Browser expressions and results stay in local browser storage. The app has no accounts, analytics, API keys, or server database. Native audio is captured only while the shortcut is held; permission can be requested in Settings before capture. Native mode stores only the chosen shortcut in local preferences. Browser mode supports typed input if microphone access is denied.

## Native source note

The native target reuses this repository's MIT-licensed `MathParser.swift` and includes a small hold-key and capture coordinator. It does not bundle a remote speech client or agent configuration.

Quit Voice Calculator from its menu, then move `~/Applications/Voice Calculator.app` to Trash. The browser app at `~/Applications/VoiceCalc.app` is separate.

To reset only native app permission decisions:

```sh
tccutil reset All com.gmperkinsmba.voicecalcstudio.native
```

To clear the native shortcut preference:

```sh
defaults delete com.gmperkinsmba.voicecalcstudio.native
```

## License

Original code is released under the MIT License. See [LICENSE](LICENSE).
