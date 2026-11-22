shader_type spatial;
// Inverted hull outline, used as the next pass of the cel material.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform float thickness = 0.025; // metres at zoom 16, scaled with distance
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	if (fade < 0.999) {
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
		if (d > fade) discard;
	}
}
