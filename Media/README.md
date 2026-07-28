Rounded-corner mask textures referenced by `Widgets/FilterChipMixin.lua`
(the main window's category filter chips) — generated procedurally
(uncompressed 32-bit TGA, 32x32, 8px corner radius) via `gen_masks.py`,
since these are flat geometric shapes rather than illustrative art:

- `RoundMaskPill.tga` — both ends rounded (a single-day event)
- `RoundMaskLeft.tga` — left end rounded, right end square (event starts here, continues right)
- `RoundMaskRight.tga` — right end rounded, left end square (event ends here, continues from left)
- `RoundMaskSquare.tga` — both ends square (event spans straight through this row)

The retail client loads `.tga`/`.png` addon textures directly (no BLP
conversion needed). If you want different corner radii or a different
category palette down the line, tweak `RADIUS`/`SIZE` in `gen_masks.py`
and rerun it rather than hand-editing pixels.

## Event bar texture

`Widgets/EventBarMixin.lua`'s bars use a diamond/chevron-pointed art style,
built from two user-supplied source images (found/made outside this addon,
not sourced from another addon):

- `CleanFullBar.tga` — a plain, textureless chevron-pointed bar shape with a
  subtle bevel (light top edge, darker bottom), 261x12.
- `BarTexture.tga` — a separate grain/crack texture (black, sparse low
  alpha), same 261x12 canvas as CleanFullBar.tga so they align exactly.
  Meant to layer on top of the clean bar rather than be part of its shape.

Both are cropped by `crop_cleanbar.py` into the pieces EventBarMixin.lua
actually uses -- fixed-size end caps plus a tileable fill strip, same
technique as the RoundMask chips above (so a pointed end/tiled grain stays
crisp no matter how wide a multi-day bar gets, instead of stretching and
distorting):

- `CleanFullBarCapLeft.tga` / `CleanFullBarCapRight.tga` — the bar's fixed
  end caps.
- `CleanFullBarFill.tga` — the bar's own base fill texture (tinted
  per-category via vertex color).
- `BarTextureFill.tga` — the grain accent layered over the fill via plain
  alpha blend (this texture is dark/sparse, so normal blending darkens the
  cracks it actually covers and leaves the rest of the fill untouched).

Rerun `crop_cleanbar.py` if `CleanFullBar.tga`/`BarTexture.tga` are ever
replaced -- its crop bounds are specific to their current layout.

`StatusBarHighlight.tga` — a solid warm-gold bar, unrelated to the fill
texture above: used for the bar's hover-highlight glow (ADD blend) instead
of a flat white tint.

An earlier round of experimentation tried several other status-bar-style
textures (a raw 512-wide source image, multiple fill/cap variants, even a
live Settings-panel dropdown to browse and compare them) before settling on
the CleanFullBar/BarTexture pairing above -- those files and that dropdown
have since been removed to keep this folder to just what's actually in use.
