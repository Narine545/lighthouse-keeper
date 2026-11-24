shader_type canvas_item;

// Post-processing: film grain + vignette + subtle cold grade.
uniform sampler2D screen_tex : hint_screen_texture;
uniform float grain_strength : hint_range(0.0, 0.15) = 0.045;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.40;
uniform float grade_strength : hint_range(0.0, 1.0) = 0.30;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec4 col = texture(screen_tex, SCREEN_UV);
	// gentle teal-amber cinematic grade
	vec3 tint = vec3(0.985, 1.015, 1.06);
	col.rgb = mix(col.rgb, col.rgb * tint, grade_strength);
	// soft vignette
	float d = distance(SCREEN_UV, vec2(0.5, 0.5));
	float v = smoothstep(0.40, 0.92, d);
	col.rgb *= 1.0 - v * vignette_strength;
	// animated film grain
	float g = hash12(SCREEN_UV * vec2(1280.0, 720.0) + vec2(TIME * 61.7, TIME * 47.3));
	col.rgb += (g - 0.5) * grain_strength;
	COLOR = col;
}
