"""Build the one game executable: <repo root>/TrioChess.exe (pck embedded, nothing else next to it).

The Windows export templates are not installed, so this does what the exporter's "embed pck" does by hand:
  1. export the game data with the Godot editor (--export-pack needs no templates)
  2. append it to a copy of the standard (non-Mono) Godot 4.7.2 binary, which runs an embedded pck
     (pck bytes, zero padding to 8 bytes, uint64 pck size, b"GDPC").
Old game builds in godot/build/ (except the web export) are removed so there is only ever one way to run the game.

Usage (from the godot/ folder):  python tools/build_exe.py
"""
import os
import shutil
import struct
import subprocess
import sys

HOME = os.path.expanduser("~")
EDITOR = os.path.join(HOME, "AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe",
                      "Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe")
RUNTIME = os.path.join(HOME, "AppData/Local/GodotStandard/Godot_v4.7.2-stable_win64.exe")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
OUT = os.path.join(os.path.dirname(ROOT), "TrioChess.exe")   # top of the repo: double-click to play
TMP_PCK = os.path.join(ROOT, ".godot", "build_exe_tmp.pck")


def main() -> int:
    if os.path.isfile(OUT):
        try:
            open(OUT, "ab").close()
        except PermissionError:
            print("TrioChess.exe is running - close the game first, then build again")
            return 1
    for p in (EDITOR, RUNTIME):
        if not os.path.isfile(p):
            print("missing:", p)
            return 1
    r = subprocess.run([EDITOR, "--headless", "--path", ROOT, "--export-pack", "Windows Desktop", TMP_PCK])
    if r.returncode != 0 or not os.path.isfile(TMP_PCK):
        print("pck export failed")
        return 1
    with open(TMP_PCK, "rb") as f:
        pck = f.read()
    os.remove(TMP_PCK)
    if pck[:4] != b"GDPC":
        print("not a pck")
        return 1
    # one executable only: old game builds in godot/build/ go (the web export is a separate target)
    if os.path.isdir(BUILD):
        for name in os.listdir(BUILD):
            if name == "web":
                continue
            p = os.path.join(BUILD, name)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    shutil.copyfile(RUNTIME, OUT)
    pad = (-(len(pck) + 12)) % 8
    with open(OUT, "ab") as f:
        f.write(pck)
        f.write(b"\0" * pad)
        f.write(struct.pack("<Q", len(pck) + pad))
        f.write(b"GDPC")
    print("built", OUT, os.path.getsize(OUT) // (1024 * 1024), "MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
