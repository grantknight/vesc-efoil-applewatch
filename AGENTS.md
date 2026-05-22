# AGENTS.md

## Project Overview

**VESC E-Foil Apple Watch App** — a native watchOS app (SwiftUI) that connects to a VESC 6.3 motor controller via Bluetooth Low Energy and displays live telemetry (battery voltage, MOSFET temp, RPM, current, watt-hours, GPS speed).

## Architecture

- **Platform**: watchOS 10.6+, built with Xcode 16.4
- **Language**: Swift 5.0
- **Frameworks**: SwiftUI, CoreBluetooth, CoreLocation (all Apple-only)
- **Dependencies**: Zero third-party dependencies
- **Build system**: Xcode project (`.xcodeproj`) — not Swift Package Manager
- **Tests**: None in the repo (no XCTest targets configured)
- **Linting**: No SwiftLint or similar configured
- **CI/CD**: None

## Source Files

| File | Imports | Platform-independent |
|---|---|---|
| `VByteArray.swift` | Foundation | Yes |
| `Packet.swift` | Foundation | Yes |
| `VescStats.swift` | Foundation, Observation | Partially (macros may differ) |
| `BluetoothManager.swift` | Foundation, CoreBluetooth | No |
| `ContentView.swift` | SwiftUI | No |
| `LocationManager.swift` | CoreLocation | No |
| `MyWatchOSAppApp.swift` | SwiftUI | No |

## Build & Run (macOS only)

1. Open `MyWatchOSApp.xcodeproj` in Xcode 16.4+
2. Select the **MyWatchOSApp Watch App** scheme
3. Choose a watchOS Simulator target (or a paired Apple Watch)
4. Press Cmd+R to build and run

## Cursor Cloud specific instructions

### Platform Constraint

This is a **pure watchOS/Apple-platform project**. It **cannot** be fully built, run, or tested on a Linux Cloud Agent VM. Xcode on macOS is required for compilation and the watchOS Simulator or physical Apple Watch is required for running.

### What CAN be done on Linux

- **Swift is installed** at `/opt/swift/usr/bin/` (Swift 6.0.3). Add to PATH: `export PATH="/opt/swift/usr/bin:$PATH"`
- **Platform-independent files** (`VByteArray.swift`, `Packet.swift`) compile and are testable on Linux using Swift Package Manager. These contain the VESC protocol serialization/deserialization logic ported from vesc_tool C++.
- To validate these files: create a temporary SPM package, copy in the source files plus the `Data.hexEncodedString` extension from `BluetoothManager.swift`, and run `swift build` / `swift test`.

### What CANNOT be done on Linux

- Full project build (requires Xcode + watchOS SDK)
- UI testing (requires watchOS Simulator or device)
- Bluetooth testing (requires physical Apple Watch + VESC hardware)
- SwiftUI previews
- Any code that imports `SwiftUI`, `CoreBluetooth`, or `CoreLocation`

### Key Gotchas

- The `Data.hexEncodedString(upperCase:)` extension is defined in `BluetoothManager.swift`, not in a standalone file. `Packet.swift` depends on it. If extracting platform-independent code for Linux testing, you must also extract this extension.
- `VescStats.swift` uses the `@Observable` macro from `Observation` framework, which may not behave identically on Linux Swift vs Apple Swift.
- The Xcode project uses `objectVersion 77` (Xcode 16.4 format) — older Xcode versions will not open it.
- No `.gitignore` exists — Xcode build artifacts and `.DS_Store` files are committed.
