shader_type canvas_item;

// Fence shadow — a pixel-exact silhouette: the real (rail-free) fence
// art's own alpha is used purely as a mask, so picket gaps stay real
// transparent gaps, and every masked-in pixel is recolored to
// shadow_color and drawn fully OPAQUE (alpha 1.0). The actual shadow
// translucency is applied exactly once, by _fence_shadow_group's own
// self_modulate.a (see overworld.gd) after every fence tile's shadow is
// composited together — see that CanvasGroup's own comment for why
// (avoids double-darkening where two shadows overlap at a corner).
//
// History: v0.2.245-247 all rotated the WHOLE fence tile rigidly around
// one fixed pivot pixel — correct for a single POINT object (why it
// worked for a lone post) but wrong for anything with width, since
// rotating a rigid shape around one point swings every OTHER point
// along an arc instead of sliding it straight out along the ground.
// v0.2.248 (per direct request with a reference photo: "the shadow
// needs to emanate from the bottom row of the fence tile, not pivot
// around a single point") first tried fixing this with a custom
// per-pixel-row shear done in THIS shader's fragment function, sampling
// a deliberately padded source texture via hand-rolled region/UV pixel
// math — that hit an unresolved Godot rendering bug (a Sprite2D with
// region_rect cropping a narrow slice out of a wider atlas rendered
// only a thin fraction of each opaque column, reproducing even with the
// custom shader removed entirely, i.e. a bug in the region_rect/scale
// pipeline itself, not in this shader's math).
//
// The fix: the desired "never move the base row; shift every row above
// it sideways-and-down, proportional to its own height above that row"
// effect is mathematically just a SHEAR — and a shear, unlike a
// per-pixel-row resample, is a plain LINEAR transform. That means it
// doesn't need a fragment shader at all: it's now done as a
// Transform2D set directly on the shadow Sprite2D node in
// _update_shadow_angles() (overworld.gd), the same way rotation/scale
// already drive the tree and person shadows. This shader is back to
// doing nothing but the recolor — no cell_origin, no shear uniforms, no
// custom UV math, and the source texture is back to its real 16x16
// per-cell size (no padding needed: a node-transform shear moves the
// whole drawn quad, so there's nothing to clip against).
uniform vec4 shadow_color : source_color = vec4(0.031, 0.055, 0.031, 0.549);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(shadow_color.rgb, a > 0.5 ? 1.0 : 0.0);
}
