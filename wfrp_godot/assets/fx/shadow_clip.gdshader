shader_type canvas_item;

// Per the request: the shadow must never render "into" the object
// casting it — specifically, never above (north of) where the
// tree's own canopy tile actually starts, since that's baked into
// the same opaque ground tile the shadow draws on top of. Reordering
// render layers can't fix this (the canopy isn't a separate node),
// so this clips per-pixel instead. The clip line is NOT necessarily
// the rotation pivot itself — for a tree, the pivot sits at the
// trunk's own middle, while the canopy starts further up, so clipping
// exactly at the pivot would wrongly discard the trunk's own upper
// half too. clip_threshold_px (in local, pre-rotation texture pixels)
// lets each shadow type set the real boundary independently of where
// its pivot happens to be.
uniform float shadow_rotation = 0.0;
uniform float clip_threshold_px = 1.0;

varying float clip_y;

void vertex() {
	float s = sin(shadow_rotation);
	float c = cos(shadow_rotation);
	clip_y = VERTEX.x * s + VERTEX.y * c;
}

void fragment() {
	if (clip_y < -clip_threshold_px) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
