shader_type canvas_item;
// Per the request: an animated, patchy cloud-shadow overlay drifting
// across the whole map — adapted from the "Animated Grassy Wind or
// Cloud Shadow Pixel Patches Overlay" shader
// (https://godotshaders.com/shader/animated-grassy-wind-or-cloud-shadow-pixel-patches-overlay/).
// Same core noise/pixel-snap/threshold-mask technique as the original,
// re-tuned here for slow-drifting cloud patches rather than fast grass
// wind (much lower wind_speed, taller/wider patches, softer opacity),
// and applied to a full-screen ColorRect using SCREEN_UV so it always
// covers the viewport regardless of the node's own size — the same
// "full-screen overlay ColorRect" pattern Overworld.gd's own
// NightOverlay already uses, just with a noise-masked alpha instead of
// a flat one. A ColorRect has no real TEXTURE of its own, so
// texture(TEXTURE, UV) below resolves to Godot's implicit blank-white
// 1x1 default — meaning `base` is effectively just this node's own
// `color` property, exactly like the reference shader was designed to
// tint whatever COLOR/TEXTURE it's applied on top of.
//
// Every uniform below is set from GDScript per real-world day (see
// Overworld._maybe_reseed_cloud_shadow() ) — deterministically seeded
// from the in-game calendar date, so the cloud pattern is stable
// within a single day but drifts to a subtly different look
// (direction/speed/patchiness/density) on the next.

uniform float wind_dir_angle = 15.0;
uniform float wind_speed = 22.0;
uniform bool use_wind_gusts = true;
uniform float patch_width_px = 320.0;
uniform float patch_height_px = 100.0;
uniform float pixel_size_px : hint_range(1.0, 64.0, 1.0) = 4.0;
uniform float rotation_degrees = 0.0;
uniform float threshold : hint_range(0.0, 1.0) = 0.62;
uniform float opacity : hint_range(0.0, 1.0) = 0.12;

// Per the follow-up request ("turn off cloud shadows inside the
// lantern/light source nimbus"): the same light-radius reveal
// NightOverlay's own shader punches through the darkness tint (see
// night_overlay_light.gdshader) is mirrored here so a drifting cloud
// patch doesn't visibly dim the ground right where the player is
// standing in their own lantern-light — set every frame from the same
// call site, Overworld._apply_light_source_overlay(). light_radius_px
// <= 0.0 (no active light right now) leaves this shader's own effect
// completely untouched, same safe-no-op convention as the night
// overlay's shader.
uniform vec2 light_center_px = vec2(-99999.0, -99999.0);
uniform float light_radius_px : hint_range(0.0, 4000.0) = 0.0;
uniform float light_softness_px : hint_range(1.0, 400.0) = 40.0;
// Real bug fix, mirroring night_overlay_light.gdshader's own fix (see
// its comment for the full story): light_center_px is in this
// project's fixed 1920x1080 design-space pixels (window/stretch/
// mode="canvas_items" lets the real OS window be any size), so the
// light-suppression distance check below has to be computed in that
// same design space too, not raw FRAGCOORD (real physical pixels) —
// UV * screen_size recovers that.
uniform vec2 screen_size = vec2(1920.0, 1080.0);

// Per the "add 2 static lamps... come on at night time" request:
// mirrors night_overlay_light.gdshader's own lamp reveal array (see
// its comment) so a drifting cloud patch doesn't dim the ground right
// under a lit lamp either, same courtesy the carried light already
// gets above. Set from the same call site, Overworld._apply_static_
// lamp_overlay().
uniform vec2 lamp_centers_px[4];
uniform int lamp_count : hint_range(0, 4) = 0;
uniform float lamp_radius_px : hint_range(0.0, 2000.0) = 0.0;
uniform float lamp_softness_px : hint_range(1.0, 400.0) = 24.0;
uniform float lamp_brightness : hint_range(0.0, 1.0) = 0.0;

// Per the "always light up the inside of building with no shadows"
// request: mirrors night_overlay_light.gdshader's own building-interior
// rectangle reveal (see its comment) so a drifting cloud patch doesn't
// dim a building's own interior floor either, while its roof is
// hidden. Set from the same call site, Overworld._apply_light_source_
// overlay().
uniform vec2 interior_rect_min_px = vec2(-99999.0, -99999.0);
uniform vec2 interior_rect_max_px = vec2(-99999.0, -99999.0);
uniform float interior_active : hint_range(0.0, 1.0) = 0.0;
uniform float interior_softness_px : hint_range(0.0, 200.0) = 24.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(a, b, u.x)
		 + (c - a) * u.y * (1.0 - u.x)
		 + (d - b) * u.x * u.y;
}

vec2 rotate(vec2 p, float angle_rad) {
	float c = cos(angle_rad);
	float s = sin(angle_rad);
	return vec2(
		p.x * c - p.y * s,
		p.x * s + p.y * c
	);
}

void fragment() {
	vec2 p = SCREEN_UV / SCREEN_PIXEL_SIZE;

	float wind_rad = radians(wind_dir_angle);
	vec2 wind_dir = -vec2(cos(wind_rad), sin(wind_rad));

	float wind_gust_speed = 1.0;
	float wind_gust_rate = 0.5;

	if (use_wind_gusts) {
		float phase = wind_gust_rate * TIME;
		float dist = wind_speed * TIME * (1.0 + 0.5 * wind_gust_speed)
				   - wind_speed * (0.5 * wind_gust_speed / wind_gust_rate)
					 * cos(phase);
		p += wind_dir * dist;
	} else {
		p += wind_dir * TIME * wind_speed;
	}

	float angle = radians(rotation_degrees);
	p = rotate(p, angle);

	p = floor(p / pixel_size_px) * pixel_size_px;

	float band = floor(p.y / patch_height_px);

	float x_noise = noise(vec2(p.x / patch_width_px, band * 0.25));
	float band_noise = hash(vec2(band, 19.0));
	float n = x_noise * 0.8 + band_noise * 0.2;

	float mask = step(threshold, n);

	vec4 base = texture(TEXTURE, UV) * COLOR;

	// Per the "remove the light overlap combiner" follow-up: reverted
	// back to max() — mirrors the same revert in night_overlay_light.
	// gdshader (see its comment for the full story on why the earlier
	// summed/stacked version was abandoned).
	float light_reveal = 0.0;
	if (light_radius_px > 0.0) {
		float light_dist = distance(UV * screen_size, light_center_px);
		light_reveal = max(light_reveal, 1.0 - smoothstep(max(light_radius_px - light_softness_px, 0.0), light_radius_px, light_dist));
	}
	if (lamp_radius_px > 0.0) {
		for (int i = 0; i < lamp_count; i++) {
			float lamp_dist = distance(UV * screen_size, lamp_centers_px[i]);
			float lamp_reveal = 1.0 - smoothstep(max(lamp_radius_px - lamp_softness_px, 0.0), lamp_radius_px, lamp_dist);
			light_reveal = max(light_reveal, lamp_reveal);
		}
	}
	if (interior_active > 0.5) {
		vec2 frag_px = UV * screen_size;
		vec2 outside = max(max(interior_rect_min_px - frag_px, frag_px - interior_rect_max_px), vec2(0.0));
		float dist_outside = length(outside);
		float interior_reveal = 1.0 - smoothstep(0.0, max(interior_softness_px, 1.0), dist_outside);
		light_reveal = max(light_reveal, interior_reveal);
	}

	base.a *= mask * opacity * (1.0 - light_reveal);
	COLOR = base;
}
