shader_type canvas_item;
// Per the follow-up request: "let's implement a map light source
// system... player should be able to turn it on/off". Applied to
// UI/NightOverlay (the same full-screen ColorRect that already carries
// the flat time-of-day darkness tint set from GDScript every frame via
// `.color`, see Overworld._apply_moon_glow_pulse()) as a SECOND,
// independent effect layered on top of that tint: a soft circular
// "hole" punched through the darkness centered on the player, sized to
// their equipped light source's actual radius (Lantern/Candle/etc, in
// tiles, converted to screen pixels from GDScript — see
// Overworld._apply_light_source_overlay()).
//
// Reuses the same "read texture(TEXTURE,UV)*COLOR, since a bare
// ColorRect has no real TEXTURE of its own" trick already established
// by cloud_shadow_overlay.gdshader — that expression just resolves to
// this node's own flat `.color` property, so this shader only ever
// ADDS the light-reveal falloff on top of whatever color/alpha
// GDScript already set that frame, rather than replacing it.
//
// light_radius_px <= 0.0 means "no active light source right now" (off,
// out of fuel, or simply not dark enough for it to matter) — the
// overlay is left completely untouched in that case, so this shader is
// a safe permanent addition to NightOverlay rather than something that
// needs to be conditionally attached/detached.

uniform vec2 light_center_px = vec2(-99999.0, -99999.0);
uniform float light_radius_px : hint_range(0.0, 4000.0) = 0.0;
uniform float light_softness_px : hint_range(1.0, 400.0) = 40.0;
// Per the follow-up request ("a bit less bright, and half again as
// bright in low light mode"): caps how far the reveal can push the
// darkness back even at the very center of the light — 1.0 would fully
// clear it (the old behaviour); Overworld._apply_light_source_overlay()
// now sends a lower value for "on" and a lower one still for "low", so
// a turned-down lantern is genuinely dimmer, not just narrower.
uniform float light_brightness : hint_range(0.0, 1.0) = 1.0;
// Real bug fix ("player light source is still not centred on the
// player character"): FRAGCOORD is the fragment's position in the
// REAL, physical window framebuffer — but this project runs with
// window/stretch/mode="canvas_items" (project.godot), which lets the
// actual OS window be any size while every other 2D/UI element (this
// ColorRect's own `size`, Overworld._apply_light_source_overlay()'s
// own get_viewport_rect().size, and the player's screen position
// Overworld computes from it) all stay in the project's fixed design
// resolution (1920x1080). The two spaces only coincide when the real
// window happens to be exactly 1920x1080; on any other window size
// (the overwhelmingly common case) FRAGCOORD drifts from
// light_center_px by the real/design scale ratio, which is exactly
// the reported bug — confirmed by force-resizing the window in a
// repro and watching the reveal circle land far from the player while
// light_center_px itself still matched the player's true design-space
// screen position exactly. UV, by contrast, is always 0-1 across this
// node's own rect regardless of physical window size — multiplying it
// back out by this node's own design-space size (screen_size, set to
// get_viewport_rect().size from the same script) recovers a pixel
// position in the SAME space light_center_px is already expressed in.
uniform vec2 screen_size = vec2(1920.0, 1080.0);

// Per the "add 2 static lamps... these should come on at night time"
// request: a second, independent set of reveal circles for fixed map
// lamps, alongside the player's own single carried-light reveal above
// — a lit lamp needs to punch its own hole in the darkness exactly the
// way a carried Lantern does, or its glow sprite (a plain additive
// Sprite2D drawn UNDER this full-screen overlay in the scene tree)
// would just get crushed back to near-black by NightOverlay's own flat
// tint on top of it, same as any other ground-level sprite at night.
// A small fixed-size array (4 slots) is simpler than a dynamic buffer
// and comfortably covers this map's 2 lamps with headroom — unused
// slots are just never counted via lamp_count. All lamps share one
// radius/softness/brightness (every lamp on the map is the same kind
// of object) rather than per-lamp uniforms, set from GDScript in
// Overworld._apply_static_lamp_overlay(), the lamps' own per-frame
// counterpart to _apply_light_source_overlay() above.
uniform vec2 lamp_centers_px[4];
uniform int lamp_count : hint_range(0, 4) = 0;
uniform float lamp_radius_px : hint_range(0.0, 2000.0) = 0.0;
uniform float lamp_softness_px : hint_range(1.0, 400.0) = 24.0;
uniform float lamp_brightness : hint_range(0.0, 1.0) = 0.0;

// Per the "always light up the inside of building with no shadows"
// request: the ONE building the player currently has the roof hidden
// for (Overworld.player_inside_building — there's only ever one, since
// a building's interior is only actually visible/rendered while its
// own roof is off) gets a full, unconditional reveal here regardless
// of any real light source — a real building has its own ambient light
// (windows, a hearth) that shouldn't depend on carrying a torch.
// Rectangular rather than circular like every light above, since a
// building's own footprint is a rectangle, not a circle — set from
// GDScript in Overworld._apply_light_source_overlay(), converted to
// this same design-space screen-pixel space every other uniform here
// already uses. interior_active <= 0.5 (no building currently
// roof-hidden) leaves this completely inert, same safe-no-op
// convention as light_radius_px <= 0.0 above.
uniform vec2 interior_rect_min_px = vec2(-99999.0, -99999.0);
uniform vec2 interior_rect_max_px = vec2(-99999.0, -99999.0);
uniform float interior_active : hint_range(0.0, 1.0) = 0.0;
// A small soft feather at the rect's own edge (matches the softness
// style of every circular light above) so the reveal doesn't cut off
// as a hard rectangular seam right at the building's own wall line.
uniform float interior_softness_px : hint_range(0.0, 200.0) = 24.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;

	// Per the "remove the light overlap combiner" follow-up: reverted
	// back to max() — overlapping light pools (the player's own carried
	// source and every lit lamp) no longer stack brighter than a single
	// light alone. The actual "combine" request turned out to be about
	// SHADOW removal (see the cross-light shadow-suppression work in
	// Overworld.gd), not brightness stacking; this shader-side change
	// was the earlier, since-abandoned interpretation.
	float reveal = 0.0;
	if (light_radius_px > 0.0) {
		float dist = distance(UV * screen_size, light_center_px);
		// 1.0 at/inside the radius core, smoothly falling to 0.0 across
		// the softness band at the edge, 0.0 (no effect) beyond it.
		reveal = max(reveal, (1.0 - smoothstep(max(light_radius_px - light_softness_px, 0.0), light_radius_px, dist)) * light_brightness);
	}
	if (lamp_radius_px > 0.0) {
		for (int i = 0; i < lamp_count; i++) {
			float lamp_dist = distance(UV * screen_size, lamp_centers_px[i]);
			float lamp_reveal = (1.0 - smoothstep(max(lamp_radius_px - lamp_softness_px, 0.0), lamp_radius_px, lamp_dist)) * lamp_brightness;
			reveal = max(reveal, lamp_reveal);
		}
	}
	if (interior_active > 0.5) {
		vec2 frag_px = UV * screen_size;
		// 0 anywhere inside the rect, growing with distance outside it
		// (per-axis, so a corner's true diagonal distance is used rather
		// than just one axis) — smoothstepped over interior_softness_px
		// into a 0..1 reveal, same shape as the circular lights' own
		// falloff above.
		vec2 outside = max(max(interior_rect_min_px - frag_px, frag_px - interior_rect_max_px), vec2(0.0));
		float dist_outside = length(outside);
		float interior_reveal = 1.0 - smoothstep(0.0, max(interior_softness_px, 1.0), dist_outside);
		reveal = max(reveal, interior_reveal);
	}
	base.a *= (1.0 - reveal);

	COLOR = base;
}
