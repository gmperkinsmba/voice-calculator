# Voice Calc

**First principle:** Show the math the person meant. Show the answer before they copy it.

Voice Calc turns a short spoken math request into an expression. You can review and edit the transcript or expression before you copy the result. Built-in speech recognition uses your browser's service when available. Support varies by browser. The provider may send speech audio to an online service. Its terms apply. Typed input works everywhere.

## Run

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

## Data

Expressions and results stay in local browser storage. The app has no accounts, analytics, API keys, or server database. You can type if microphone access is denied.

## License

Original code is released under the MIT License. See [LICENSE](LICENSE).
