shader_type canvas_item;

// Постобработка: лёгкий подъём насыщенности, мягкая виньетка,
// тонкое плёночное зерно — картина приобретает фактуру.

uniform sampler2D screen_tex : hint_screen_texture;
uniform float time_s = 0.0;
uniform vec2 screen_px = vec2(1280.0, 720.0);

float hash21(vec2 p) {
        p = fract(p * vec2(234.34, 435.345));
        p += dot(p, p + 34.23);
        return fract(p.x * p.y);
}

void fragment() {
        vec3 col = texture(screen_tex, SCREEN_UV).rgb;

        float lum = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(vec3(lum), col, 1.14);

        vec2 q = SCREEN_UV - 0.5;
        col *= 1.0 - dot(q, q) * 0.38;

        float gr = hash21(SCREEN_UV * screen_px + vec2(fract(time_s * 11.3) * 71.0));
        col += (gr - 0.5) * 0.014;

        COLOR = vec4(col, 1.0);
}
