# AutoScanSystem

A UE4SS Lua mod for **Star Trek: Voyager – Across the Unknown** that automatically scans all Points of Interest in a solar system when you manually scan any one of them.

## What it does

When you scan a POI in a system, the mod detects the completed scan and propagates it to every other unscanned POI in the same solar system — one at a time, with a short delay between each so the game can settle. System-level scans (the "Scan System" action from the sector map) are ignored and do not trigger propagation.

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) experimental build compatible with UE 5.6
- `dwmapi.dll` (UE4SS proxy DLL) present in:
  `<Steam>\steamapps\common\Star Trek Voyager - Across the Unknown\STVoyager\Binaries\Win64\`

## Installation

### Step 1 — Install UE4SS

1. Download the latest **experimental** release of [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) (`UE4SS_v*.*.*.zip`).
2. Extract the zip. You'll get a `dwmapi.dll` and a `ue4ss\` folder.
3. Copy both into the game's Win64 binaries folder:
   ```
   <Steam>\steamapps\common\Star Trek Voyager - Across the Unknown\STVoyager\Binaries\Win64\
   ```
4. Open `ue4ss\UE4SS-settings.ini` in a text editor and confirm these values are set:
   ```ini
   [General]
   bUseUObjectArrayCache = false

   [EngineVersionOverride]
   MajorVersion = 5
   MinorVersion = 6
   ```
5. Launch the game once to confirm UE4SS loads — check `ue4ss\UE4SS.log` for `[UE4SS]` startup lines.

### Step 2 — Install AutoScanSystem

1. From the release zip, copy both folders into `Win64\ue4ss\`:
   - `AutoScanSystem\` → `Win64\ue4ss\Mods\AutoScanSystem\`
   - `UE4SS_Signatures\` → `Win64\ue4ss\UE4SS_Signatures\`

   The final structure should be:
   ```
   Win64\ue4ss\
   ├── Mods\
   │   └── AutoScanSystem\
   │       ├── enabled.txt
   │       └── Scripts\
   │           └── main.lua
   └── UE4SS_Signatures\
       └── StaticConstructObject.lua
   ```

2. **Launch the game.**

To verify it's running, check `ue4ss\UE4SS.log` — you should see `[AutoScanSystem] v1.2 loaded`.

## Compatibility

- Compatible alongside pak mods (e.g. mods installed to `Content\Paks\~mods\`).
- Does not modify any game files.

## Version

**v1.2** — see [Releases](../../releases) for changelog.

## License

MIT — see [LICENSE](LICENSE).
