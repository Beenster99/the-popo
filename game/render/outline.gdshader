shader_type spatial;
// Inverted hull outline, used as the next pass of the cel material. The hull
// is pushed out in screen space, so lines stay the same pixel width at every
// zoom level of the isometric camera.
// Phase 1.7 (beenster: "the cells are drawing black too much"): the lines
// are a soft charcoal rather than black, thinner, and in the third-person
// view they thin out with distance so far-off walls and rubble don't turn
// into a black scribble. Settings > Graphics > Outlines sets the strength.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform float thickness = 0.025; // kept for older callers; unused
uniform float width_px = 2.0;
// 0 no lines, 1 the old full black lines.
uniform float strength = 0.55;
instance uniform float fade = 1.0;
varying float v_keep;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_pos;
	vec3 vn = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy;
	if (length(dir) > 0.0001) {
		dir = normalize(dir);
	}
	float w = width_px * mix(0.45, 1.0, strength);
	// Perspective camera: lines fade out past about 12 m and are gone by 45 m.
	bool persp = PROJECTION_MATRIX[3][3] < 0.5;
	float far_k = persp ? clamp(1.0 - (-view_pos.z - 12.0) / 33.0, 0.0, 1.0) : 1.0;
	v_keep = far_k;
	clip.xy += dir / VIEWPORT_SIZE * w * max(far_k, 0.35) * 2.0 * clip.w;
	// Godot 4 uses reversed depth (bigger z is nearer), so the hull is pushed
	// away by lowering z. Raising it, as before, pulled the hull in front of
	// the mesh in the perspective view: far buildings and people went black.
	clip.z -= 0.0002 * clip.w;
	POSITION = clip;
	// v0.8.1: past the fade the hull is thrown out of view instead of being
	// drawn and discarded pixel by pixel (a big cost at 4K).
	if ((persp && far_k <= 0.0) || strength < 0.01) {
		POSITION = vec4(0.0, 0.0, -10.0, 1.0);
	}
}

void fragment() {
	if (strength < 0.01 || v_keep < 0.01) {
		discard;
	}
	ALBEDO = mix(vec3(0.3, 0.29, 0.33), outline_color.rgb, strength);
	float f = fade * mix(0.6, 1.0, strength) * smoothstep(0.0, 0.5, v_keep);
	if (f < 0.999) {
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
		if (d > f) discard;
	}
}
