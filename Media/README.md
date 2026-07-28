Rounded-corner mask textures referenced by `Widgets/EventBarMixin.lua`
(`SetMask`) — generated procedurally (uncompressed 32-bit TGA, 32x32,
8px corner radius) via `gen_masks.py`, since these are flat geometric
shapes rather than illustrative art:

- `RoundMaskPill.tga` — both ends rounded (a single-day event)
- `RoundMaskLeft.tga` — left end rounded, right end square (event starts here, continues right)
- `RoundMaskRight.tga` — right end rounded, left end square (event ends here, continues from left)
- `RoundMaskSquare.tga` — both ends square (event spans straight through this row)

The retail client loads `.tga`/`.png` addon textures directly (no BLP
conversion needed). If you want different corner radii or a different
category palette down the line, tweak `RADIUS`/`SIZE` in `gen_masks.py`
and rerun it rather than hand-editing pixels.
