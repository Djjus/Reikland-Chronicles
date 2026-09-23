shader_type canvas_item;

// Per the "shadow should be the inverted shape of the visible post"
// request: a fence shadow is a straight COPY of the fence tile's own
// real art (same texture region, same atlas orientation), drawn as a
// flat shadow colour instead of its real brown/wood colours. Only the
// source texture's ALPHA is used, as a mask — every genuinely opaque
// post/rail pixel becomes shadow_color, every transparent gap pixel
// stays fully transparent, so the shadow's silhouette is a pixel-exact
// match of the visible fence, gaps and all.
uniform vec4 shadow_color : source_color = vec4(0.03, 0.055, 0.03, 0.62);
// Per the follow-up "it does not emanate from the fence correctly ...
// should emanate from the bottom of the post" correction: a plain
// TRANSLATION (moving the whole 16x16 copy sideways) was wrong — it
// slides the post's own foot away from the real post's foot, so the
// shadow reads as a disconnected floating duplicate instead of
// something cast FROM the post, the same way every other shadow in
// this game (walls extruded from their own footprint edge, trees/
// people rotating from a fixed base pivot) stays anchored at the real
// object's base. Fixed with a SHEAR instead of a translation: every
// fence tile is drawn as a plain, unrotated 16x16 blit regardless of
// orientation (the "vertical"/corner variants are pre-rotated PIXELS
// in the source art, not a runtime transform — see the vertical atlas
// tile's own comment in overworld.gd), so the tile's own bottom edge
// (VERTEX.y == 16, local pixel space) consistently represents "where
// this tile touches the ground," exactly matching how every other
// fence tile in the run is drawn. Vertices AT that edge get shifted by
// nothing at all — they stay glued to the real post's own foot — and
// vertices further from it (toward VERTEX.y == 0, the top of a tall
// post) are shifted progressively more, same as a real shadow cast by
// a vertical object: the taller part reaches further along the ground.
uniform vec2 shadow_extension = vec2(0.0, 0.0);
uniform float shadow_base_y = 16.0;
// Per the "fence shadows emanate northward, over the northward arc,
// while all other shadows go via the south-facing arc" report (two
// rounds after the base-anchoring fix above): re-negating
// `shadow_extension` on the GDScript side didn't fix it, which rules
// out a simple sign error in the direction vector — the user's own
// screenshots kept showing the same north-leaning read regardless.
// The actual cause: for FENCE_VERTICAL_ATLAS and the four corner
// atlases (all derived from the horizontal tile via an axis
// TRANSPOSE — see overworld.gd's own comment on FENCE_VERTICAL_ATLAS),
// the transpose turns the horizontal tile's two full-height post
// COLUMNS (a clean "foot at the bottom, tip at the top" shape) into
// two thin post ROWS sitting near this tile's own top and bottom
// edges — there's no single feature left that reads as "a foot
// planted at the bottom." With the anchor fixed at VERTEX.y==16 (this
// tile's bottom), the near-anchor row is shifted almost nothing and
// sits almost perfectly behind the real (unshifted) art — fully
// hidden — while the row near VERTEX.y==0 (this tile's top) is
// shifted the most and is what actually escapes hiding and becomes
// visible. So the visible shadow mass always sits up near this
// tile's own top edge, reading as "north," regardless of which way
// `shadow_extension` itself points — the anchor choice, not the
// extension's sign, decides where the visible mass sits.
// `anchor_from_top` flips which edge is the "stays put" anchor for
// exactly these transposed atlases (set from GDScript per-tile, based
// on which atlas coords _resolve_fence_atlas() picked) so the visible
// mass sits near THIS tile's bottom (south) instead, matching every
// other shadow's south-leaning arc. The plain horizontal atlas is
// untouched — it already has genuine bottom-anchored post columns and
// was never reported wrong.
uniform bool anchor_from_top = false;

void vertex() {
	float t;
	if (anchor_from_top) {
		t = clamp(VERTEX.y / shadow_base_y, 0.0, 1.0);
	} else {
		t = clamp((shadow_base_y - VERTEX.y) / shadow_base_y, 0.0, 1.0);
	}
	VERTEX += shadow_extension * t;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a);
}
