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
   After copying, the folder should contain at minimum:
   ```
   Win64\
   ├── dwmapi.dll          ← UE4SS proxy DLL
   ├── ue4ss\
   │   ├── UE4SS.dll
   │   ├── Mods\
   │   └── ...
   └── STVoyager-Win64-Shipping.exe
   ```
4. Launch the game once to confirm UE4SS loads (a console window will appear, or check `ue4ss\UE4SS.log`).

### Step 2 — Install AutoScanSystem

1. Copy the `AutoScanSystem\` folder from this repo into the UE4SS mods directory:
   ```
   Win64\ue4ss\Mods\AutoScanSystem\
   ```
   The final structure should be:
   ```
   AutoScanSystem\
   ├── enabled.txt
   └── Scripts\
       └── main.lua
   ```

2. **Launch the game.** No further configuration needed.
   The mod loads automatically because `enabled.txt` is present.

To verify it's running, open the UE4SS console — you should see:
```
[AutoScanSystem] v1.1 loaded
```

## Compatibility

- Compatible alongside pak mods (e.g. mods installed to `Content\Paks\~mods\`).
- Does not modify any game files.

## Version

**v1.1** — see [Releases](../../releases) for changelog.

## License

MIT — see [LICENSE](LICENSE).
