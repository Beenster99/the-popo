shader_type spatial;
// Inverted hull outline, used as the next pass of the cel material. The hull
// is pushed out in screen space, so lines stay the same pixel width at every
// zoom level of the isometric camera.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform float thickness = 0.025; // kept for older callers; unused
uniform float width_px = 2.0;
instance uniform float fade = 1.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 vn = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy;
	if (length(dir) > 0.0001) {
		dir = normalize(dir);
	}
	clip.xy += dir / VIEWPORT_SIZE * width_px * 2.0 * clip.w;
	clip.z += 0.0002 * clip.w; // nudge back so the hull never covers its own mesh
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	if (fade < 0.999) {
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
		if (d > fade) discard;
	}
}
