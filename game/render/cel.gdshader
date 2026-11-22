shader_type spatial;
// Cel shading: diffuse light quantised into bands, a hard rim, and a small
// specular pop. Shadows from the sun are respected, so cover reads clearly.

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.35;
uniform vec4 shadow_tint : source_color = vec4(0.55, 0.6, 0.85, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float specular_size : hint_range(0.0, 1.0) = 0.06;
uniform float fade : hint_range(0.0, 1.0) = 1.0; // 1 visible, 0 hidden (roof fading)

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_tex, UV).rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (fade < 0.999) {
		// Screen-door dither so roofs fade without sorting problems.
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
		if (d > fade) discard;
	}
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float q = floor(ndl * bands + 0.5) / bands;
	q = max(q, 0.0);
	vec3 lit = mix(shadow_tint.rgb * shadow_floor, vec3(1.0), q);
	DIFFUSE_LIGHT += ALBEDO * lit * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = step(1.0 - specular_size, dot(NORMAL, h)) * step(0.5, ndl);
	SPECULAR_LIGHT += spec * LIGHT_COLOR * 0.15;
	float rim = (1.0 - dot(NORMAL, VIEW)) * pow(ndl, 0.3);
	DIFFUSE_LIGHT += step(rim_threshold, rim) * rim_amount * LIGHT_COLOR * ALBEDO;
}
