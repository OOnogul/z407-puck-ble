# z407

A macOS command-line remote for the Logitech Z407 speaker. It talks to the speaker over Bluetooth LE, so you can control it without the original dial.

This project is unofficial and not affiliated with Logitech.

## Requirements

- macOS
- Xcode Command Line Tools (for the Swift compiler): `xcode-select --install`
- A Logitech Z407 with its original dial's batteries removed (the speaker accepts one control connection at a time)

## Build

```
./build.sh
```

This creates the `z407` program. `build.sh` embeds `Info.plist`, which macOS needs to grant Bluetooth access.

## Use

Run the menu:

```
./z407
```

Type a number to send that command once. Add a count to repeat it, for example `4 4` sends bass down four times over one connection. Counts go from 1 to 50.

| No. | Action |
|---|---|
| 1 | Volume up |
| 2 | Volume down |
| 3 | Bass up |
| 4 | Bass down |
| 5 | Play/pause |
| 6 | Next track |
| 7 | Previous track |
| 8 | Input: Bluetooth |
| 9 | Input: AUX |
| 10 | Input: USB |
| 11 | Pairing mode |
| 12 to 14 | Chimes 1 to 3 |

Type `q` to quit.

For scripts, pass a command name:

```
./z407 volume-up
./z407 bass-down --timeout 45
```

Factory reset needs an explicit flag, and it's only available from the command line:

```
./z407 factory-reset --yes
```

## Notes

- Volume and bass change one step per press. The speaker doesn't report its level, so the program can't show it.
- Each command waits up to 30 seconds for the speaker before giving up.
- Repeated presses are spaced 0.3 seconds apart.
- Set `Z407_DEBUG=1` to print each Bluetooth step to the terminal.

## Protocol

The commands and handshake come from freundTech's reverse-engineering notes: [logi-z407-reverse-engineering](https://github.com/freundTech/logi-z407-reverse-engineering).

## Credits

Code written with Kiro, an AI-powered IDE, with model Claude Haiku 5.5, under the direction of onogulo.

## License

MIT. See [LICENSE](LICENSE).
