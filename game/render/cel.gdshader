shader_type spatial;
// Cel shading: diffuse light quantised into bands, a hard rim, and a small
// specular pop. Shadows from the sun are respected, so cover reads clearly.

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// v0.25: a texture's alpha 0 marks mortar or grout, drawn this colour
// whatever the surface is tinted (a red brick wall keeps grey mortar).
uniform vec3 grout_color : source_color = vec3(0.68, 0.66, 0.62);
uniform bool grout_alpha = false;
// Kit textures are mapped in metres; this is 1 / the metres one tile covers.
uniform float uv_scale = 1.0;
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float specular_size : hint_range(0.0, 1.0) = 0.06;
// Per-object fade for roofs and upper floors (1 visible, 0 hidden). An
// instance uniform, so pieces can share one material and still fade alone.
instance uniform float fade = 1.0;
// See-through surfaces (glass) use the same screen-door dither.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// v0.25.1: merged meshes (furniture) carry each part's colour per vertex, so
// a whole prop is one surface and one draw instead of one per colour.
uniform bool use_vertex_color = false;

void fragment() {
	vec4 t = texture(albedo_tex, UV * uv_scale);
	ALBEDO = grout_alpha ? mix(grout_color * t.rgb, albedo.rgb * t.rgb, t.a) : albedo.rgb * t.rgb;
	if (use_vertex_color) {
		// The colours are stored as picked (sRGB), like albedo; Forward+
		// lights in linear space, so they are converted the same way.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ALBEDO *= COLOR.rgb;
#else
		vec3 c = COLOR.rgb;
		ALBEDO *= mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
#endif
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (fade * opacity < 0.999) {
		// Screen-door dither so roofs fade without sorting problems.
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
		if (d > fade * opacity) discard;
	}
}

void light() {
	// Banded diffuse. Only lit bands are added here; the unlit side gets the
	// scene's ambient light, which carries the cool shadow tint. (A constant
	// "shadow floor" per light would leak every lamp's colour across its
	// whole cluster at night.)
	// Bands are taken on the light's real intensity (energy included), so a
	// street lamp makes a crisp pool rather than vanishing below the first band.
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float e = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b)) / PI;
	float q = floor(ndl * e * bands + 0.35) / bands;
	DIFFUSE_LIGHT += ALBEDO * q * (LIGHT_COLOR / max(e * PI, 0.0001));
	vec3 h = normalize(LIGHT + VIEW);
	float spec = step(1.0 - specular_size, dot(NORMAL, h)) * step(0.5, ndl);
	SPECULAR_LIGHT += spec * LIGHT_COLOR * 0.15;
	float rim = (1.0 - dot(NORMAL, VIEW)) * pow(ndl, 0.3);
	DIFFUSE_LIGHT += step(rim_threshold, rim) * rim_amount * LIGHT_COLOR * ALBEDO / PI;
}
