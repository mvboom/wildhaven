shader_type spatial;
// Wildhaven mist curtain — Tier 1 row 13 (Mist) VISUAL layer.
//
// PROPOSAL, NOT YET HUMAN-APPROVED (see project/scripts/world/mist_boundary.gd's header and
// the build report): a ground-hugging, softly mottled fog band standing at the world's
// revealed edge. Every uniform below is a look-affecting judgment call, not a GDD number —
// flagged for the human under Proposals rather than silently decided here.
//
// Authored in-repo from primitive shader math (a hash-based value-noise function) — no
// third-party texture or asset, matching the grey-box placeholder convention
// (project/assets/placeholder/README.md): nothing here needs an attribution entry.
//
// unshaded: directional-light shadow terms on a translucent curtain would read as a lit
// solid object, exactly the "hard wall" look gdd.md's "a curtain, not a gate" rules out.
// cull_disabled: each of the four panels is viewed from the inside of the revealed world
// only in ordinary play, but double-siding costs nothing at four quads and removes any risk
// of a panel vanishing if the camera ever ends up briefly on its far side.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, shadows_disabled;

// Base fog colour. Warm-leaning, pulled back from full saturation/pure white per art.md's
// palette rule ("no pure black or pure white"). PROPOSAL — the human's to retune.
uniform vec4 mist_color : source_color = vec4(0.86, 0.88, 0.87, 1.0);

// How opaque the curtain reads at ground/eye level, before the height fade below applies.
// Deliberately short of 1.0 — "something the player can't see through/past yet," not an
// opaque wall (gdd.md: "the mist is a curtain, not a gate").
uniform float base_alpha : hint_range(0.0, 1.0) = 0.82;

// Vertical fade band, in world units (1 unit = 1 tile = person-scale, gdd.md -> Level &
// world design). Below `fade_start_height` the curtain sits at full `base_alpha`; between
// the two heights it fades to fully clear; above `fade_end_height` nothing renders. Chosen so
// the band fully covers the player's eye height (~0.9, camera_rig.gd's CameraRig offset) and
// clears well before it reads as a sky-blocking wall — PROPOSAL, the human's eyeball call.
uniform float fade_start_height : hint_range(0.0, 10.0) = 1.4;
uniform float fade_end_height : hint_range(0.0, 20.0) = 4.5;

// Static, position-derived mottling so the band reads as uneven mist rather than one flat
// painted plane. Deliberately NOT time-animated — row 13's own thin_form is "instant, no
// sprouting," and an ambient drift is exactly the depth/animation call spec.md #19 reserves
// for later, not this pass's to add.
uniform float mottle_strength : hint_range(0.0, 1.0) = 0.22;
uniform float mottle_scale : hint_range(0.01, 2.0) = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Cheap deterministic hash / value noise. No texture lookup, no external asset — matches
// mist_reveal.gd's own "pure function of position" contract in spirit, though this is a
// purely visual mottle and carries no gameplay meaning.
float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float _value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float height_fade = 1.0 - smoothstep(fade_start_height, fade_end_height, world_pos.y);
	float mottle = _value_noise(world_pos.xz * mottle_scale + world_pos.y * mottle_scale * 0.5);
	float alpha = base_alpha * height_fade * mix(1.0 - mottle_strength, 1.0, mottle);
	ALBEDO = mist_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
