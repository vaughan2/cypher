# Cypher

A macOS menu bar utility that locks your screen with a Matrix-style rain animation on demand. Press a hotkey to cover all displays with an animated overlay that blocks all input — press it again to instantly return to your work.

![Cypher demo](docs/demo.gif)

## Features

- Matrix rain animation across all connected displays
- Blocks all keyboard shortcuts (Cmd+Tab, Mission Control, Spaces, brightness keys, etc.)
- Mouse ripple effect — characters bloom and push away from the cursor
- Menu bar icon shows lock state at a glance
- Launch at Login toggle built in
- 60fps display-synced animation

## Requirements

- macOS 11.0+
- Xcode Command Line Tools (`xcode-select --install`)
- Go 1.21+

## Install

### Homebrew (recommended)

```sh
brew tap vaughan2/tools
brew install cypher
```

### Build from source

```sh
git clone https://github.com/vaughan2/cypher
cd cypher
make install   # builds and copies to /Applications
```

## Permissions

Two permissions are required — macOS will prompt for both on first use:

| Permission | Purpose |
|---|---|
| **Input Monitoring** | Register the global hotkey (Cmd+Shift+L) |
| **Accessibility** | Block Cmd+Tab, Mission Control, and system shortcuts while locked |

Grant them in **System Settings → Privacy & Security**, then relaunch.

## Usage

| Action | How |
|---|---|
| Lock screen | `Cmd+Shift+L` |
| Unlock | `Cmd+Shift+L` |
| Toggle from menu | Click the lock icon in the menu bar |
| Launch at Login | Menu bar → Launch at Login |
| Quit | Menu bar → Quit |

## Development

```sh
git clone https://github.com/vaughan2/cypher
cd cypher
make build          # builds hotkey-incognito.app in the current directory
make clean          # removes build artifacts
```

The project is a single Go + Objective-C file (`app.m`) linked against Cocoa, Carbon, and QuartzCore via CGo.

## License

MIT — see [LICENSE](LICENSE).
