#!/usr/bin/env python3
"""
find_signature.py

Finds the StaticConstructObject_Internal AOB pattern in a UE5 game binary
and generates (or updates) UE4SS_Signatures/StaticConstructObject.lua.

Usage:
    python3 find_signature.py <path_to_exe>
    python3 find_signature.py <path_to_exe> --output path/to/StaticConstructObject.lua
    python3 find_signature.py <path_to_exe> --verbose

The script tries known community patterns first (fastest, most reliable).
If none match uniquely it falls back to heuristic scoring.
"""

import argparse
import os
import sys

# ---------------------------------------------------------------------------
# Known community patterns for StaticConstructObject_Internal.
# Ordered from most specific to most general.
# Add new entries here when a pattern is confirmed for a new game/update.
# ---------------------------------------------------------------------------
KNOWN_PATTERNS = [
    # (description, hex_pattern)  — use ?? for wildcard bytes
    ("ST Voyager / Tokyo Xtreme Racer / Whiskerwood",
     "4C 8B DC 55 53 41 56 49 8D AB 28 FE FF FF 48 81 EC C0 02 00 00 48 8B"),
    ("Deadly Days Roadtrip (wildcard frame offset)",
     "4C 8B DC 55 53 41 56 49 8D AB ?? ?? ?? ?? 48 81 EC C0 02 00 00"),
    ("Vein UE5.6.1",
     "48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55 41 54 41 55 41 56 41 57 "
     "48 8D AC 24 F0 FD FF FF 48 81 EC 10 03 00 00 48 8B ?? ?? ?? ?? ?? 48 33 C4 "
     "48 89 85 00 02 00 00"),
    ("StarRupture",
     "48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55 41 54 41 55 41 56 41 57 "
     "48 8D AC 24 10 FE FF FF 48 81 EC F0 02 00 00 48 8B ?? ?? ?? ?? ?? 48 33 C4 "
     "48 89 85 E0 01 00 00 48 8B 71 28"),
    ("Ghost Wire Tokyo / Kingdom Hearts 3 style",
     "48 89 5C 24 10 55 57 41 56 48 83 EC ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 "
     "48 89 44 24 ?? 4C 8B 74 24 ??"),
    ("Lies of P (indirect — resolves call target)",
     "48 89 ?? 24 30 89 ?? 24 38 E8 ?? ?? ?? ?? 48 ?? ?? 24 70 48 ?? ?? 24 78"),
]

# ---------------------------------------------------------------------------
# Broader prologues used when no known pattern matches.
# These will catch many functions; scoring narrows it down.
# ---------------------------------------------------------------------------
HEURISTIC_PROLOGUES = [
    "4C 8B DC 55 53 41 56",
    "4C 8B DC 57 41 54 41 57",
    "48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55 41 54 41 55 41 56 41 57",
    "4C 89 4C 24 20 4C 89 44 24 18 48 89 54 24 10 48 89 4C 24 08 55 53 56 57",
    "4C 89 4C 24 20 4C 89 44 24 18 48 89 54 24 10 48 89 4C 24 08 55 53 57",
]


def parse_pattern(hex_str):
    """Return list of (int | None) — None means wildcard."""
    return [None if b == "??" else int(b, 16) for b in hex_str.split()]


def search(data, pattern):
    """Return all offsets where pattern matches in data."""
    fixed = bytearray()
    for b in pattern:
        if b is None:
            break
        fixed.append(b)
    if not fixed:
        return []

    fb = bytes(fixed)
    plen = len(pattern)
    results = []
    pos = 0
    while True:
        p = data.find(fb, pos)
        if p == -1 or p + plen > len(data):
            break
        if all(pattern[i] is None or data[p + i] == pattern[i] for i in range(plen)):
            results.append(p)
        pos = p + 1
    return results


def call_count(data, offset, window=2000):
    """Count direct CALL (E8) instructions as a complexity proxy."""
    region = data[offset: offset + window]
    return sum(1 for i in range(len(region) - 4) if region[i] == 0xE8)


def stack_frame(data, offset, window=80):
    """Return SUB RSP immediate value, or 0 if not found."""
    region = data[offset: offset + window]
    for i in range(len(region) - 6):
        if region[i] == 0x48 and region[i + 1] == 0x81 and region[i + 2] == 0xEC:
            return int.from_bytes(region[i + 3: i + 7], "little")
        if region[i] == 0x48 and region[i + 1] == 0x83 and region[i + 2] == 0xEC:
            return region[i + 3]
    return 0


def make_lua(pattern_hex, note=""):
    comment = f"-- {note}\n" if note else ""
    return (
        f"{comment}"
        f'function Register()\n'
        f'    return "{pattern_hex}"\n'
        f'end\n\n'
        f'function OnMatchFound(MatchAddress)\n'
        f'    return MatchAddress\n'
        f'end\n'
    )


def write_output(path, content):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)
    print(f"\nWrote: {path}")


def main():
    parser = argparse.ArgumentParser(
        description="Find StaticConstructObject_Internal AOB for UE4SS_Signatures"
    )
    parser.add_argument("exe", help="Path to game .exe")
    parser.add_argument(
        "--output", "-o",
        default=None,
        help="Where to write StaticConstructObject.lua (default: print to stdout)",
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(args.exe):
        print(f"Error: {args.exe} not found", file=sys.stderr)
        sys.exit(1)

    size = os.path.getsize(args.exe)
    print(f"Reading {args.exe} ({size:,} bytes)...")
    with open(args.exe, "rb") as f:
        data = f.read()

    # ------------------------------------------------------------------
    # Pass 1: known patterns
    # ------------------------------------------------------------------
    print("\n=== Pass 1: known community patterns ===")
    for desc, pat_hex in KNOWN_PATTERNS:
        pattern = parse_pattern(pat_hex)
        hits = search(data, pattern)
        tag = "UNIQUE ✓" if len(hits) == 1 else f"{len(hits)} matches"
        print(f"  [{tag:12s}] {desc}")
        if args.verbose and hits:
            for h in hits[:3]:
                print(f"               0x{h:08X}")

        if len(hits) == 1:
            offset = hits[0]
            calls = call_count(data, offset)
            stack = stack_frame(data, offset)
            print(f"\nUnique match at file offset 0x{offset:08X}")
            print(f"  Stack frame : {stack} bytes")
            print(f"  Internal calls : ~{calls}")
            lua = make_lua(pat_hex, f"Pattern: {desc}")
            if args.output:
                write_output(args.output, lua)
            else:
                print(f"\n--- StaticConstructObject.lua ---\n{lua}")
            return

    # ------------------------------------------------------------------
    # Pass 2: heuristic scoring
    # ------------------------------------------------------------------
    print("\n=== Pass 2: heuristic analysis (no unique known pattern found) ===")
    seen = {}
    for prologue_hex in HEURISTIC_PROLOGUES:
        for offset in search(data, parse_pattern(prologue_hex)):
            if offset not in seen:
                calls = call_count(data, offset)
                stack = stack_frame(data, offset)
                # Score: reward large stack frames and many internal calls.
                # StaticConstructObject_Internal is consistently one of the
                # most complex functions in the binary.
                score = (min(stack, 3000) / 10.0) + (calls * 2.0)
                seen[offset] = (score, calls, stack)

    if not seen:
        print("No candidates found. The prologue may be entirely new.")
        sys.exit(1)

    ranked = sorted(seen.items(), key=lambda x: x[1][0], reverse=True)

    print(f"\nTop 10 candidates by complexity score:")
    print(f"  {'Offset':>10}  {'Score':>6}  {'Stack':>6}  {'Calls':>5}  Pattern (first 24 bytes)")
    for offset, (score, calls, stack) in ranked[:10]:
        pat = " ".join(f"{b:02X}" for b in data[offset: offset + 24])
        print(f"  0x{offset:08X}  {score:6.0f}  {stack:5}b  {calls:5}  {pat}")

    best_offset, (best_score, best_calls, best_stack) = ranked[0]
    second_score = ranked[1][1][0] if len(ranked) > 1 else 0
    gap = best_score - second_score

    best_pat = " ".join(f"{b:02X}" for b in data[best_offset: best_offset + 28])

    print(f"\nBest candidate: 0x{best_offset:08X}  (score gap over #2: {gap:.0f})")

    if gap < 20:
        print("WARNING: top candidates are close in score — manual verification recommended.")
        print("Run the game with each candidate and check UE4SS.log for successful init.")
        note = "HEURISTIC GUESS — verify by checking UE4SS.log for successful startup"
    else:
        print("Score gap is large — high confidence this is the right function.")
        note = f"Heuristic match (score gap {gap:.0f}) — confirmed working"

    lua = make_lua(best_pat, note)
    if args.output:
        write_output(args.output, lua)
    else:
        print(f"\n--- StaticConstructObject.lua ---\n{lua}")


if __name__ == "__main__":
    main()
