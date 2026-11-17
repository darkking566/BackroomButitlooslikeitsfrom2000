shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 water_tint : source_color = vec3(0.16, 0.21, 0.26);
uniform float water_opacity : hint_range(0.1, 0.9) = 0.46;
uniform float ripple_speed : hint_range(0.0, 4.0) = 1.1;
uniform float ripple_scale : hint_range(2.0, 30.0) = 12.0;
uniform float ripple_strength : hint_range(0.0, 0.4) = 0.14;
uniform float pixel_density : hint_range(24.0, 128.0) = 56.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// 像素化 UV 保留 PS2 復古顆粒感
	vec2 p_uv = floor(UV * pixel_density) / pixel_density;
	vec2 centered = p_uv - vec2(0.5);

	// 不規則水窪邊緣（非方正矩形）
	float wobble = (value_noise(p_uv * 5.5) - 0.5) * 0.26 + (value_noise(p_uv * 11.0) - 0.5) * 0.10;
	float dist = length(centered) + wobble;
	float edge_mask = 1.0 - smoothstep(0.32, 0.46, dist);
	if (edge_mask < 0.05) {
		discard;
	}

	// 動態水波紋法線擾動，讓日光燈與手電筒照過去有流動反光
	float t = TIME * ripple_speed;
	float n1 = sin(p_uv.x * ripple_scale + t) * cos(p_uv.y * ripple_scale - t * 0.8);
	float n2 = sin((p_uv.x + p_uv.y) * ripple_scale * 0.75 - t * 1.2);
	float wave = (n1 + n2) * 0.5;

	NORMAL = normalize(vec3(wave * ripple_strength, 1.0, (n1 - n2) * ripple_strength));

	ALBEDO = water_tint + vec3(0.03, 0.04, 0.05) * max(wave, 0.0);
	ROUGHNESS = 0.03;
	METALLIC = 0.18;
	SPECULAR = 0.92;
	ALPHA = water_opacity * edge_mask;
}
