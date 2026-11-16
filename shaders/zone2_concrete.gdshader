shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.60, 0.62, 0.64);
uniform vec3 grid_color : source_color = vec3(0.30, 0.32, 0.34);
uniform float roughness_val : hint_range(0.05, 1.0) = 0.88;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float tile_grid_strength : hint_range(0.0, 1.0) = 0.0;
uniform float tile_scale : hint_range(0.3, 4.0) = 0.85;
uniform float noise_strength : hint_range(0.0, 0.3) = 0.07;

uniform float jitter_resolution : hint_range(60.0, 480.0) = 160.0;
uniform float affine_strength : hint_range(0.0, 1.0) = 0.72;

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
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 n = abs(world_normal);

	vec2 base_uv;
	if (n.y > 0.5) {
		base_uv = world_pos.xz;
	} else if (n.x > n.z) {
		base_uv = vec2(world_pos.z, world_pos.y);
	} else {
		base_uv = vec2(world_pos.x, world_pos.y);
	}

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
	float grain = (hash21(p_uv * 24.0) - 0.5) * noise_strength;
	float patch_n = (hash21(floor(uv * 1.4)) - 0.5) * (noise_strength * 0.65);

	vec3 col = base_color + grain + patch_n;

	if (tile_grid_strength > 0.01) {
		vec2 tile_uv = fract(p_uv / tile_scale);
		float is_grid = clamp(step(tile_uv.x, 0.055) + step(tile_uv.y, 0.055), 0.0, 1.0);
		col = mix(col, grid_color, is_grid * tile_grid_strength);
	}

	ALBEDO = clamp(col, 0.0, 1.0);
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
}
