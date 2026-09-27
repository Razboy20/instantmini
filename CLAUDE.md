# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

instantspaces patches the macOS Dock in-process to reduce animation durations for:
- **Spaces switching** - Desktop/Space transitions
- **Window minimize/unminimize** - Genie, Scale and Suck effects, including "Minimize windows into application icon"

Uses LLDB to inject a scripting addition payload that patches ARM64 instructions controlling animation timing.

**Requirements:** SIP disabled, Xcode Command Line Tools, Apple Silicon (arm64e), macOS 14+ (Sonoma, Sequoia, Golden Gate)

## Build Commands

```bash
make                    # Build payload.dylib (arm64e)
make install            # Build and install to /Library/ScriptingAdditions/
make uninstall          # Remove installed osax
make clean              # Remove built artifacts
```

## Usage

```bash
# Restart Dock, then inject
killall Dock
sudo ./scripts/inject.sh [MODE] [FEATURES]

# Examples:
sudo ./scripts/inject.sh min0125 all      # Default: all features, 0.125s
sudo ./scripts/inject.sh zero spaces      # Only spaces, instant
sudo ./scripts/inject.sh min0125 minimize # Only minimize animations
```

## Architecture

```
src/payload.m           # Objective-C payload injected into Dock
├── PatternSpec         # Struct: pattern, patch_offset, name, feature flags
├── g_patterns[]        # All patterns with metadata
├── instantspaces_patch()   # Main export: pattern-match and patch
├── instantspaces_verify()  # Verifies patches were applied
└── constructor (ctor)      # Auto-runs patch on dylib load

scripts/
├── inject.sh           # Manual injection: inject.sh [MODE] [FEATURES]
├── auto-inject.sh      # LaunchAgent wrapper with retry logic
├── install.sh          # Build + install osax bundle
└── uninstall.sh        # Remove osax bundle
```

### Pattern System

Each `PatternSpec` contains:
- `pattern`: Hex bytes with `??` wildcards
- `patch_offset`: Byte offset within match to apply patch (0 for spaces, 4 for minimize)
- `name`: Descriptive name for logging
- `feature`: `FEATURE_SPACES` or `FEATURE_MINIMIZE`
- `os_min` / `os_max`: Inclusive macOS major version range (`0` = unbounded)

Every pattern whose feature is enabled and whose version range contains the current OS is applied
to all of its matches.

**Spaces patterns** (patch at offset 0 - first instruction):
- `00 10 6A 1E E0 03 14 AA ...` - Sonoma only
- `00 10 6A 1E A8 ?? ?? D1 ...` - Sequoia and later

**Minimize patterns** (macOS 15 Sequoia and 27 Golden Gate, both arm64e and arm64e.x1 slices):

`bl`/`adrp` immediates shift between Dock builds, so they are always wildcarded.
- `-[DockBar effectDur]` is swizzled via the ObjC runtime to return the mode's duration (no byte pattern)
- `-[Spaces prepareWindowForMinMax:duration:]` is swizzled to floor `duration` at 0.25s. It adds the
  window to a temporary "min-max-space" and destroys it after `duration`; destroying it immediately
  races Dock's window ordering and strands the window (invisible after app relaunch).
- Never skip the animated min/max branches: they set `transactionID` (reply to the app),
  pair `beginMinMax`/`endMinMax`, and call `prepareWindowForMinMax` (adds the window to the
  current Space). Skipping them leaves unminimized windows invisible. Only shorten durations.

**Minimize-to-app-icon patterns** (patch at offset 4 - the `d8` duration assignment):

With "Minimize windows into application icon" enabled, Dock bypasses `effectDur` and
hardcodes a per-effect duration into `d8`, then moves it to `d0` (`fmov d0, d8` on Sequoia,
`mov v0.16b, v8.16b` on Golden Gate) before calling the global animation-duration setter.
- `00 1C 21 1E 08 C0 22 1E ?? ?? ?? ?? ?? ?? ?? 97` - Genie (`genie-speed` pref, default 0.5s)
- `01 10 6A 1E 28 1C 60 1E ?? ?? ?? ?? ?? ?? ?? 97` - Scale (0.25s)
- `01 10 62 1E 08 1C 61 1E ?? ?? ?? ?? ?? ?? ?? 97` - Suck (0.4s)

Each minimize-to-app pattern appears twice in Dock (minimize + unminimize logic).

### Environment Variables

- `INSTANTSPACES_MODE`: `zero` | `min0125` (default: `zero`)
- `INSTANTSPACES_FEATURES`: `all` | `spaces` | `minimize` (default: `all`)

### Modes

- **zero** (`0x2f00e400`): `movi d0, #0` - instant (0.0s)
- **min0125** (`0x1e681000`): `fmov d0, #0.125` - near-instant (0.125s)

## Adding New Patterns

1. Add entry to `g_patterns[]` in `src/payload.m`:
   ```c
   { .pattern = "XX XX ?? XX", .patch_offset = 4, .name = "name",
     .feature = FEATURE_*, .os_min = 0, .os_max = 0 },
   ```
2. Set `patch_offset` to the `fmov`/`movi` that writes the duration register (it is replaced
   with `movi d<Rd>, #0` or `fmov d<Rd>, #0.125`, keeping the original `Rd`)
3. Wildcard `bl`/`adrp`/branch immediates; verify the pattern matches every Dock slice
4. Rebuild and test

## Logs

- Console.app: filter "Dock" and "[instantspaces]"
- File: `/private/var/tmp/instantspaces.<DockPID>.log`

Expected output shows per-feature breakdown:
```
[instantspaces] Patched [minimize-to-app-scale] @0x...: 0x1e601c28 -> 0x2f00e408
[instantspaces] [effectDur] swizzled -[DockBar effectDur]
[instantspaces] [min-max-space] swizzled -[Spaces prepareWindowForMinMax:duration:]
[instantspaces] Patched: spaces=1, minimize=8
```

## Version Control

This project uses Jujutsu (jj), not Git. Use `jj` commands for all VCS operations.
