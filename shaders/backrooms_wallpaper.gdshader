shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.73, 0.69, 0.38);
uniform vec3 stripe_color : source_color = vec3(0.62, 0.58, 0.31);
uniform vec3 pattern_color : source_color = vec3(0.49, 0.45, 0.25);
uniform vec3 baseboard_color : source_color = vec3(0.42, 0.39, 0.22);

uniform float jitter_resolution : hint_range(60.0, 480.0) = 160.0;
uniform float affine_strength : hint_range(0.0, 1.0) = 0.72;

varying vec2 v_uv_persp;
varying vec2 v_uv_affine;
varying float v_w;
varying float v_world_y;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 n = abs(world_normal);
	float horiz = (n.x > n.z) ? world_pos.z : world_pos.x;

	vec2 base_uv = vec2(horiz, world_pos.y);
	v_world_y = world_pos.y;

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

	// Low-res 32px-per-meter pixelated wallpaper grid
	vec2 p_uv = floor(uv * 32.0) / 32.0;

	// Vertical stripes (0.45m period)
	float col_phase = fract(p_uv.x * 2.2);
	float is_dark_stripe = step(0.55, col_phase);
	vec3 col = mix(base_color, stripe_color, is_dark_stripe);

	// Classic Level 0 chevron/arrow motif inside the lighter stripe
	float cell_x = fract(p_uv.x * 2.2) / 0.55; // 0..1 inside light band
	float cell_y = fract(p_uv.y * 2.8);
	float chevron = abs(cell_x - 0.5) * 1.4;
	float arrow_band = step(0.0, cell_y - chevron - 0.15) * step(cell_y - chevron - 0.15, 0.22);
	float inner_arrow = (1.0 - is_dark_stripe) * arrow_band;
	col = mix(col, pattern_color, inner_arrow * 0.75);

	// Pixelated grime/damp noise
	float grain = (hash21(p_uv * 24.0) - 0.5) * 0.08;
	col += grain;

	// Damp lower baseboard
	if (v_world_y < 0.12) {
		col = baseboard_color + grain * 0.5;
	} else if (v_world_y < 0.42) {
		col *= 1.0 - (0.42 - v_world_y) * 0.25;
	}

	ALBEDO = clamp(col, 0.0, 1.0);
	ROUGHNESS = 0.92;
}
