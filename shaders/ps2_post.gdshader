shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float pixel_size : hint_range(1.0, 6.0) = 3.0;
uniform float color_levels : hint_range(8.0, 64.0) = 20.0;
uniform float dither_strength : hint_range(0.0, 0.08) = 0.025;
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.22;

float bayer4x4(vec2 pos) {
	int x = int(mod(pos.x, 4.0));
	int y = int(mod(pos.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return (m[idx] / 16.0) - 0.5;
}

void fragment() {
	vec2 px_coord = floor(FRAGCOORD.xy / pixel_size);
	vec2 snapped_uv = (px_coord * pixel_size + 0.5 * pixel_size) * SCREEN_PIXEL_SIZE;
	vec3 col = texture(screen_texture, snapped_uv).rgb;

	// PSX ordered dithering + 15-bit style color quantization
	col += bayer4x4(px_coord) * dither_strength;
	col = floor(col * color_levels + 0.5) / color_levels;

	// Subtle vignette
	vec2 centered = SCREEN_UV - 0.5;
	float vig = 1.0 - dot(centered, centered) * vignette_strength * 2.0;
	col *= clamp(vig, 0.0, 1.0);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
