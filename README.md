# ClaudeMulti

Control multiple Claude Code sessions from your phone. A Mac host manages iTerm2 sessions while an Android companion provides a mobile command interface over the local network.

## Architecture

```
┌──────────────────────────────────────────────┐
│  Mac Host (SwiftUI)                          │
│                                              │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  │
│  │ Session  │  │ WebSocket │  │ Screen   │  │
│  │ Manager  │──│ Server    │──│ Capture  │  │
│  └──────────┘  └─────┬─────┘  └──────────┘  │
│       │              │              │         │
│       ▼              │              ▼         │
│  ┌──────────┐        │        ┌──────────┐   │
│  │ iTerm2   │        │        │ Accessib. │  │
│  │ Bridge   │        │        │ Reader   │   │
│  └──────────┘        │        └──────────┘   │
│                      │                        │
└──────────────────────┼────────────────────────┘
                       │  WiFi / WebSocket
┌──────────────────────┼────────────────────────┐
│  Android Companion   │   (Jetpack Compose)    │
│                      │                        │
│  ┌──────────┐  ┌─────┴─────┐  ┌──────────┐   │
│  │ Session  │  │ WebSocket │  │ mDNS     │   │
│  │ Cards    │──│ Client    │──│ Discovery│   │
│  └──────────┘  └───────────┘  └──────────┘   │
│                                               │
└───────────────────────────────────────────────┘
```

## Prerequisites

| Requirement | Version |
|---|---|
| macOS | 13.0+ (Ventura or later) |
| Xcode CLI tools or Xcode | 15+ (Swift 5.9) |
| iTerm2 | 3.x |
| Android Studio | Hedgehog+ (for the Android app) |
| Android device | API 28+ (Android 9) |

Both devices must be on the same local network for WebSocket communication.

## Quick Start

### Mac Host

```bash
cd mac-app && swift build
.build/debug/ClaudeMulti
```

On first launch, grant the required permissions when prompted (see table below).

### Android Companion

Open `android-app/` in Android Studio, build and run on your device.

### Pairing

1. Start the Mac app -- the dashboard shows a 6-digit pairing code.
2. Open the Android app on the same WiFi network.
3. The app auto-discovers the Mac via mDNS, or you can enter the Mac's IP manually.
4. Enter the 6-digit code on Android to pair.

Once paired, the Android app displays all active Claude Code sessions and lets you cycle between them, send text, and monitor output.

## Project Structure

```
ClaudeMulti/
├── mac-app/              # Swift package — Mac host application
│   ├── Package.swift
│   └── Sources/
├── android-app/          # Kotlin — Android companion app
│   ├── build.gradle.kts
│   └── app/
├── protocol/             # Shared WebSocket protocol definition
│   ├── schema/           #   JSON Schema (messages.json)
│   ├── examples/         #   Example payloads for every message type
│   └── README.md         #   Protocol documentation
├── scripts/              # Dev tooling
│   └── check-protocol-sync.sh
└── README.md
```

## Protocol

All communication uses JSON over WebSocket. Every message carries a `type` discriminator and an integer `version` field. See [`protocol/README.md`](protocol/README.md) for the full specification, message catalog, and flow diagrams.

## Validating Protocol Sync

Run the validation script to confirm both platforms can parse the shared protocol:

```bash
./scripts/check-protocol-sync.sh
```

This checks that the JSON schema and examples are valid, the Swift models compile, and the Kotlin conformance tests pass.

## Required Permissions

### Mac

| Permission | Why |
|---|---|
| Accessibility | Read iTerm2 session content via the accessibility tree |
| Screen Recording | Capture terminal screen regions for state sync |
| Automation (iTerm2) | Send keystrokes and commands to iTerm2 via AppleScript |

### Android

| Permission | Why |
|---|---|
| Local Network / WiFi | Discover and connect to the Mac host |

## License

MIT
