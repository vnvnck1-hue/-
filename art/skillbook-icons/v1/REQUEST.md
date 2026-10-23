# Codex request: grade skill book icons (4)

Please generate 4 inventory icons with your built-in image generation tool (image_gen), one per skill book grade.
Each must be a separate transparent PNG (real alpha background).

Save the results in this folder (`art/skillbook-icons/v1/`) as:
- `skillbook1.png` — 일반 (common): grey/silver-blue cover
- `skillbook2.png` — 희귀 (rare): sky blue cover
- `skillbook3.png` — 영웅 (epic): violet/purple cover
- `skillbook4.png` — 전설 (legendary): orange-gold cover

Attached images are style references: the existing sword and shield icons, plus the current "봉인된 스킬북" (sealed skill book) icon.
Match the style of the existing item icons exactly.

## Shared prompt (use for all 4)

Use case: stylized-concept
Asset type: individual transparent PNG inventory icon for a cute fantasy RPG, matching the supplied existing sword and shield style.
Style: very thick clean near-black rounded outlines, chunky simplified silhouette, saturated flat color regions, one simple shaded facet and a small cream highlight. Smooth cartoon illustration, easy to recognize at 32 and 48 pixels. Avoid delicate engraving or tiny details.
Composition: exactly ONE closed hardcover spell book, centered in a square canvas, filling roughly 75-80% of the canvas with generous transparent padding on all sides. All parts fully inside the canvas. Slight three-quarter view showing the front cover, the spine and a cream page edge.
Backdrop: genuinely transparent alpha. No ground, no scene, no card, no frame around the canvas, no label, no letters or numbers, no watermark. No diffuse glow outside the item, no blurred effects, no particle field. Magical accents must be a few solid, clearly outlined shapes attached close to the item.
Input images are style references only.

All 4 books must share the same silhouette, angle and size so they read as one set; they differ by cover colour and by how ornate the trim is (a clear upgrade ladder):

1. skillbook1 (일반): plain grey-silver leather cover, simple dark corner caps, a small round silver emblem in the centre of the cover. Modest, no gems.
2. skillbook2 (희귀): bright sky-blue cover, silver corner caps and a silver clasp, a round emblem with one small blue gem.
3. skillbook3 (영웅): rich violet-purple cover, gold corner caps and gold clasp, a gold emblem with a glowing purple gem, a ribbon bookmark hanging out.
4. skillbook4 (전설): warm orange-gold cover, ornate gold corner caps, gold clasp, a large star-shaped gold emblem with a fiery orange gem, ribbon bookmark, and two or three small solid outlined sparkle shapes attached close to the book.

## After generating

- Copy each final image into this folder with the exact filenames above (do not overwrite anything outside this folder).
- Write `generation-manifest.json` here, in the same format as `art/special-icons/v1-complete/generation-manifest.json` (created date, mode, sharedPrompt, styleReferences, and per-asset id/name/subject/filename/source/prompt).
- Verify each PNG has a real transparent background (corner pixels alpha 0) and report the result.
