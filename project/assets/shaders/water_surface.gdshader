shader_type spatial;
// Wildhaven water terrain surface — Water.tscn (project/assets/terrain/water/).
//
// PROPOSAL, NOT YET HUMAN-APPROVED: every uniform below is a look-affecting judgment
// call, not a GDD number — flagged for the human under Proposals, same posture as
// mist_curtain.gdshader (this file's structural precedent).
//
// Authored in-repo from primitive shader math (fresnel depth-tint + a uniform shimmer
// pulse — see the removed-ripple note below) — no third-party texture or asset, so no
// attribution entry is needed (same "no asset" posture as mist_curtain.gdshader). art.md's
// own plan for Water was always "shader/plane, no model" — this is that plan, not a
// substitute for it.
//
// shadows_disabled: a shadow cast onto/by a thin animated translucent surface reads as a
// dark smear rather than depth, at this tile scale and camera distance — same reasoning
// mist_curtain.gdshader used for its own curtain.
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx, shadows_disabled;

// Depth-tint gradient: DEEP_COLOR reads head-on (looking straight down through the
// surface), SHALLOW_COLOR brightens in at grazing angles (the fixed ~45 camera pitch
// means every water tile shows some of both). Not a real refraction/depth-buffer read —
// a fresnel-driven mix standing in for one, cheap enough for every water tile on screen
// at once.
uniform vec4 deep_color : source_color = vec4(0.07, 0.24, 0.42, 0.88);
uniform vec4 shallow_color : source_color = vec4(0.28, 0.58, 0.62, 0.55);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;

// GEOMETRIC RIPPLE REMOVED (2026-08-16, human-reported, second report with more detail:
// "lines... fade in in one direction, fade out, and then fade in another direction and
// then fade out"). That description is not a shading bug — it is an exact description of
// what the previous two-term sin/cos vertex displacement actually was: two independent
// directional wavefronts (one running along X at speed `t`, one along Z at speed `1.2t`),
// each periodically catching a specular highlight along its crest as it travels, then
// losing it, while the other term's crest picks up — i.e. two traveling line patterns
// beating against each other. Recomputing NORMAL from the displacement (the first fix
// attempt) was mathematically correct and fixed the flat-normal/bent-geometry MISMATCH,
// but did nothing about this, because this was never a mismatch — it was the wave shape
// itself. Any additive sin/cos VERTEX displacement inherently produces traveling parallel
// highlight bands; the fix is to stop using spatial sine terms for motion at all, not to
// patch them further.
//
// Replaced with a UNIFORM (position-independent) brightness pulse — a single
// time-based sine with no VERTEX.x/VERTEX.z term anywhere, so it is structurally
// incapable of producing a line, band, or directional pattern: every fragment on every
// water tile brightens and dims together, in phase, with nothing to travel across the
// surface. This keeps "some indication of water" alive (the shimmer) without
// reintroducing the artifact class this human report is the second round of. The static
// fresnel depth-tint gradient below (deep vs. shallow color) was already doing most of
// the "reads as water" work on its own and is unchanged.
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.4;
uniform float shimmer_strength : hint_range(0.0, 0.3) = 0.08;

// SPARKLE/GLINT ADDED (2026-08-16, human-reported: "water looks better, no lines... but it
// does look rather flat"). Root cause of the flatness: with the ripple gone, NORMAL is a
// constant (0,1,0) everywhere and VIEW barely changes across one small tile (or even
// several nearby tiles, at this camera distance), so `fresnel` above is nearly the same
// value across the whole surface — the depth-tint gradient alone reads as one near-solid
// color instead of "water." Rather than bring back any geometric or directional-color
// motion (the exact artifact class the two prior reports were about), this adds small
// twinkling highlights — like sunlight catching individual ripples — using WORLD-SPACE
// cells (`world_pos.xz`, a varying computed in vertex() from MODEL_MATRIX, continuous
// across every water tile with no per-tile seam) hashed together with a TIME value that is
// floor()'d into discrete steps. Each step re-randomizes which cells glint, so individual
// sparkles appear and disappear in place — they never slide across the surface in a
// direction, so this cannot reproduce the "fades in one direction" artifact class. Kept
// sparse (sparkle_probability default 0.06) per this pass's "variety without noise" brief.
uniform float sparkle_density : hint_range(1.0, 20.0) = 5.0;
uniform float sparkle_probability : hint_range(0.0, 0.3) = 0.06;
uniform float sparkle_speed : hint_range(0.0, 5.0) = 1.2;
uniform float sparkle_brightness : hint_range(0.0, 1.0) = 0.4;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.15;
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Cheap 2D hash, not a real PRNG — deterministic per-cell, which is exactly what a
// twinkling-cell effect needs (same cell, same TIME step, always the same result).
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), fresnel_power);
	vec4 tinted = mix(deep_color, shallow_color, fresnel);
	float shimmer = 1.0 + sin(TIME * shimmer_speed) * shimmer_strength;
	vec3 albedo = tinted.rgb * shimmer;

	// SPARKLE SOFTENED (2026-08-25, human-reported: "plain blue background with light blue
	// blocks that disappear and reappear... does not look like good water" — screenshot showed
	// hard-edged rectangles, not a twinkle). Root cause: the previous version lit or didn't
	// light an ENTIRE cell with a binary step() and no falloff, so a lit cell was a flat-filled
	// square that popped fully on then fully off — a blinking tile, not a highlight. Same
	// per-cell hash/probability/cadence as before (so sparkle_density/probability/speed keep
	// their existing meaning), but the glint itself is now a small soft dot at a jittered point
	// WITHIN the cell (smoothstep falloff, not a hard edge) whose brightness eases in and out
	// smoothly across the cell's lifetime (sin() pulse) instead of an abrupt on/off pop.
	float time_raw = TIME * sparkle_speed;
	float time_cell = floor(time_raw);
	vec2 cell = floor(world_pos.xz * sparkle_density);
	vec2 cell_uv = fract(world_pos.xz * sparkle_density);
	float n = hash21(cell + vec2(time_cell * 13.13, time_cell * 27.77));
	float lit = step(1.0 - sparkle_probability, n);
	vec2 point = vec2(hash21(cell + 91.7), hash21(cell + 47.3));
	float falloff = 1.0 - smoothstep(0.0, 0.35, length(cell_uv - point));
	float temporal = sin(PI * fract(time_raw));
	float glint = lit * falloff * temporal;
	albedo += glint * sparkle_brightness * vec3(1.0, 1.0, 0.95);

	// SCREEN-SPACE DITHER ADDED (2026-08-25, human-reported web-build screenshot: crisp
	// parallel bands running the length of a river). Root cause: the fresnel term above is
	// a genuinely smooth, continuous gradient (VIEW varies with actual camera distance even
	// under this project's orthogonal projection), but an 8-bit-per-channel framebuffer with
	// no output dithering quantizes that smooth gradient into visible discrete steps — banding,
	// not a shading bug, and not the same artifact class as the removed geometric ripple above
	// (this reproduces on a long, slowly-varying gradient with NO time/position-based motion
	// at all). Desktop GL contexts commonly dither the final framebuffer write by default;
	// WebGL/ANGLE commonly does not, which is why this showed up in the web build. Fixed with
	// a tiny per-pixel noise offset (reusing hash21(), mod()'d down to keep FRAGCOORD small
	// for mediump precision) sized at roughly one 8-bit step — enough to break the quantization
	// bands, far too small to be visible as noise or to change the intended look/tuning.
	albedo += (hash21(mod(FRAGCOORD.xy, 32.0)) - 0.5) / 255.0;

	ALBEDO = albedo;
	ALPHA = tinted.a;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
}
