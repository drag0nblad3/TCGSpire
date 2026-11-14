"""Pack nine approved 3x3 source sheets without repainting their pixels.

Usage: python3 tools/pack_neon_enemies.py ember.png tide.png bloom.png void.png
       chrome.png noise.png neutral1.png neutral2.png neutral3.png
Requires Pillow. Source sheets stay outside the runtime repository.
"""
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


def cells(path, first_neutral=False):
    image = Image.open(path).convert("RGBA")
    assert image.width == image.height and image.width % 3 == 0
    side = image.width // 3
    # The approved first neutral source's third row starts slightly early.
    # Use the visible gutters so its knight's crest doesn't leak into the lurker.
    rows = [0, side, round(image.height * 810 / 1254), image.height] if first_neutral else [0, side, side * 2, image.height]
    result = []
    for slot in range(9):
        column, row = slot % 3, slot // 3
        columns = [0, side, round(image.width * 804 / 1254), image.width] if first_neutral and row == 2 else [0, side, side * 2, image.width]
        crop = image.crop((columns[column], rows[row], columns[column + 1], rows[row + 1]))
        # Preserve the complete square composition and original alpha.
        crop.thumbnail((340, 340), Image.Resampling.LANCZOS)
        cell = Image.new("RGBA", (340, 340))
        cell.paste(crop, ((340 - crop.width) // 2, (340 - crop.height) // 2))
        result.append(cell)
    return result


def main(paths):
    assert len(paths) == 9, "Expected six faction sheets and three neutral sheets"
    out = Path(__file__).resolve().parents[1] / "assets/combat/neon"
    out.mkdir(parents=True, exist_ok=True)
    keys = ["ember", "tide", "bloom", "void", "chrome", "noise", "neutral"]
    sources = {key: [paths[i]] for i, key in enumerate(keys[:6])}
    sources["neutral"] = paths[6:]
    manifest = {"cell_size": [440, 340], "sheets": {}}
    for key in keys:
        sprites = [cell for i, path in enumerate(sources[key]) for cell in cells(path, key == "neutral" and i == 0)]
        columns = 5 if key == "neutral" else 3
        rows = (len(sprites) + columns - 1) // columns
        atlas = Image.new("RGBA", (columns * 440, rows * 340))
        for i, sprite in enumerate(sprites):
            atlas.paste(sprite, (i % columns * 440 + 50, i // columns * 340))
        atlas.save(out / (key + ".webp"), lossless=True, method=6)
        manifest["sheets"][key] = {
            "columns": columns,
            "base_count": len(sprites) - 2,
            "elite_rear_slot": len(sprites) - 2,
            "elite_front_slot": len(sprites) - 1,
            "sources": [{"name": Path(p).name, "sha256": hashlib.sha256(Path(p).read_bytes()).hexdigest()} for p in sources[key]],
        }
    (out / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
