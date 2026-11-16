shader_type spatial;

uniform vec3 carpet_color : source_color = vec3(0.49, 0.45, 0.26);
uniform float jitter_resolution : hint_range(60.0, 480.0) = 160.0;
uniform float affine_strength : hint_range(0.0, 1.0) = 0.12;

varying vec2 v_uv_persp;
varying vec2 v_uv_affine;
varying float v_w;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 654.21));
	p += dot(p, p + 34.45);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 base_uv = world_pos.xz;

	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip_pos.w > 0.001) {
		vec3 ndc = clip_pos.xyz / clip_pos.w;
		float grid_x = jitter_resolution * 1.7777;
		float grid_y = jitter_resolution;
		ndc.x = floor(ndc.x * grid_x + 0.5) / grid_x;
		ndc.y = floor(ndc.y * grid_y + 0.5) / grid_y;
		clip_pos.xyz = ndc * clip_pos.w;
	}
	POSITION = clip_pos;

	float safe_w = max(clip_pos.w, 0.25);
	v_uv_persp = base_uv;
	v_uv_affine = base_uv * safe_w;
	v_w = safe_w;
}

void fragment() {
	vec2 affine_uv = v_uv_affine / max(v_w, 0.25);
	vec2 uv = mix(v_uv_persp, affine_uv, affine_strength);

	vec2 p_uv = floor(uv * 28.0) / 28.0;
	float n1 = hash21(p_uv * 24.0);
	float n2 = hash21(floor(uv * 2.0));
	vec3 col = carpet_color + (n1 - 0.5) * 0.11 + (n2 - 0.5) * 0.06;
	ALBEDO = clamp(col, 0.0, 1.0);
	ROUGHNESS = 0.98;
}
