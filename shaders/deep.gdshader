shader_type canvas_item;

// Фон «Тихой глубины» — это картина, написанная шейдером:
// глубинный градиент, дрейфующий туман, световые столбы от поверхности,
// каустика, сияние и цветение — плюс мягкий свет игрока.

uniform float time_s = 0.0;
uniform vec2 screen_px = vec2(1280.0, 720.0);
uniform vec2 light_pos = vec2(640.0, 400.0);
uniform float light_r = 140.0;
uniform float light_i = 1.0;
uniform float bloom_evt = 0.0;
uniform float aurora = 0.0;
uniform vec2 sway = vec2(0.0, 0.0);

// Метаболы: сглаженное поле из шаров света (xy — позиция в px,
// z — радиус, w — сила) и их цвета. Свет игрока, медузы и кит
// сливаются в одну живую массу — адаптация техники
// godotshaders.com/shader/sdf-metaballs (smin после Inigo Quilez).
uniform vec4 balls[8];
uniform vec3 ball_cols[8];
uniform int balls_n = 0;
uniform float balls_k = 55.0;

float hash21(vec2 p) {
        p = fract(p * vec2(234.34, 435.345));
        p += dot(p, p + 34.23);
        return fract(p.x * p.y);
}

float vnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + vec2(1.0, 0.0));
        float c = hash21(i + vec2(0.0, 1.0));
        float d = hash21(i + vec2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int k = 0; k < 4; k++) {
                v += a * vnoise(p);
                p = p * 2.03 + vec2(17.7, 9.2);
                a *= 0.5;
        }
        return v;
}

// Поле метаболов: сглаженный минимум расстояний со слиянием цветов.
vec4 ball_field(vec2 p) {
        float d = 1e5;
        vec3 c = vec3(0.0);
        for (int i = 0; i < balls_n; i++) {
                float di = length(p - balls[i].xy) - balls[i].z;
                vec3 ci = ball_cols[i];
                if (i == 0) {
                        d = di;
                        c = ci;
                } else {
                        float k = max(balls_k, 1e-4);
                        float h = clamp(0.5 + 0.5 * (di - d) / k, 0.0, 1.0);
                        c = mix(ci, c, h);
                        d = mix(di, d, h) - k * h * (1.0 - h);
                }
        }
        return vec4(c, d);
}

// Рельеф бездны: реймарчинг SDF-сцены со smooth CSG и туманом по глубине —
// адаптация техники godotshaders.com «Fullscreen SDF Raymarching with Smooth
// CSG and Depth»: примитивы и операторы после Inigo Quilez, цвета сливаются
// вместе с поверхностями (classic metaball melt).
float sd_ellipsoid(vec3 p, vec3 c, vec3 r) {
        vec3 q = (p - c) / r;
        return (length(q) - 1.0) * min(r.x, min(r.y, r.z));
}

vec4 smerge(vec4 a, float d, vec3 col, float k) {
        k = max(k, 1e-4);
        float h = clamp(0.5 + 0.5 * (d - a.w) / k, 0.0, 1.0);
        return vec4(mix(col, a.rgb, h), mix(d, a.w, h) - k * h * (1.0 - h));
}

vec4 ssub(vec4 a, float d, float k) {
        k = max(k, 1e-4);
        float h = clamp(0.5 - 0.5 * (d + a.w) / k, 0.0, 1.0);
        return vec4(a.rgb, mix(a.w, -d, h) + k * h * (1.0 - h));
}

// Сцена: пять сглаженных сфероидов — холмы бездны + вырез (грот).
vec4 map_abyss(vec3 p, float t) {
        vec3 slate = vec3(0.010, 0.026, 0.046);
        vec3 tealr = vec3(0.018, 0.052, 0.068);
        vec4 acc = vec4(slate, sd_ellipsoid(p, vec3(-320.0, -140.0, 520.0), vec3(380.0, 300.0, 260.0)));
        acc = smerge(acc, sd_ellipsoid(p, vec3(180.0, -180.0, 760.0), vec3(460.0, 340.0, 300.0)), tealr, 110.0);
        acc = smerge(acc, sd_ellipsoid(p, vec3(740.0 + 40.0 * sin(t * 0.05), -110.0, 560.0), vec3(340.0, 280.0, 240.0)), slate, 120.0);
        acc = smerge(acc, sd_ellipsoid(p, vec3(1140.0, -200.0, 820.0), vec3(430.0, 360.0, 280.0)), tealr, 100.0);
        acc = smerge(acc, sd_ellipsoid(p, vec3(480.0, -240.0, 980.0), vec3(560.0, 420.0, 320.0)), slate, 130.0);
        acc = ssub(acc, sd_ellipsoid(p, vec3(520.0, 40.0, 640.0), vec3(150.0, 110.0, 130.0)), 80.0);
        return acc;
}

// Тетраэдральная нормаль (4 касания) — как в шейдере-источнике.
vec3 abyss_normal(vec3 p, float t) {
        float e = 2.0;
        vec2 k = vec2(1.0, -1.0);
        return normalize(
                k.xyy * map_abyss(p + k.xyy * e, t).w +
                k.yyx * map_abyss(p + k.yyx * e, t).w +
                k.yxy * map_abyss(p + k.yxy * e, t).w +
                k.xxx * map_abyss(p + k.xxx * e, t).w);
}

void fragment() {
        vec2 px = UV * screen_px;
        float y = UV.y;

        // Глубинный градиент: бирюза у поверхности — почти чёрный индиго внизу.
        vec3 c_top = vec3(0.045, 0.20, 0.24);
        vec3 c_up = vec3(0.030, 0.10, 0.16);
        vec3 c_mid = vec3(0.014, 0.045, 0.095);
        vec3 c_bot = vec3(0.006, 0.012, 0.028);
        vec3 col = mix(c_top, c_up, smoothstep(0.0, 0.28, y));
        col = mix(col, c_mid, smoothstep(0.22, 0.62, y));
        col = mix(col, c_bot, smoothstep(0.55, 1.0, y));

        // Дрейфующий туман — живописная дымка толщи воды.
        vec2 fuv = UV + sway * 0.02;
        float fog = fbm(vec2(fuv.x * 3.2 + time_s * 0.015, fuv.y * 2.1 - time_s * 0.008));
        float fogmask = smoothstep(0.05, 0.45, y) * (1.0 - smoothstep(0.55, 0.95, y));
        col = mix(col, vec3(0.030, 0.10, 0.16), fog * fogmask * 0.35);

        // Световые столбы, качающиеся от поверхности.
        float rays = 0.0;
        for (int k = 0; k < 3; k++) {
                float fk = float(k);
                float xw = fuv.x * (5.0 + fk * 2.3) + fk * 2.7 + sin(time_s * 0.07 + fk * 1.9) * 0.6;
                float band = pow(0.5 + 0.5 * sin(xw * 1.7 + sin(fuv.y * 2.4 + time_s * 0.11 + fk * 2.1) * 0.35), 4.0);
                float fall = pow(1.0 - y, 2.2);
                rays += band * fall;
        }
        col += vec3(0.10, 0.28, 0.30) * rays * 0.18;

        // Каустика у поверхности — преломлённый свет.
        float ca = sin((UV.x * 26.0) + time_s * 0.9 + sin(UV.y * 18.0 + time_s * 0.7) * 2.0);
        float cb = sin((UV.x * 21.0) - time_s * 0.8 + cos(UV.y * 15.0 - time_s * 0.6) * 2.4);
        float caust = pow(max(ca * cb, 0.0), 3.0);
        col += vec3(0.20, 0.55, 0.55) * caust * (1.0 - smoothstep(0.02, 0.22, y)) * 0.22;

        // Сама поверхность воды — дрожащий светлый слой.
        float surf = 1.0 - smoothstep(0.0, 0.035, y);
        float shim = 0.5 + 0.5 * sin(UV.x * 40.0 + time_s * 1.1 + sin(UV.x * 13.0 - time_s * 0.6) * 2.0);
        col += vec3(0.35, 0.75, 0.72) * surf * (0.25 + 0.35 * shim) * 0.5;

        // Сияние (аврора) над поверхностью — редкое событие.
        if (aurora > 0.001) {
                float band = smoothstep(0.20, 0.02, y);
                float cur = fbm(vec2(UV.x * 5.0 + time_s * 0.08, y * 3.0 - time_s * 0.05));
                float w = pow(cur, 2.0) * band * aurora;
                vec3 acol = mix(vec3(0.15, 0.75, 0.45), vec3(0.45, 0.25, 0.75), sin(UV.x * 6.0 + time_s * 0.2) * 0.5 + 0.5);
                col += acol * w * 0.55;
        }

        // Цветение воды: поднимающиеся световые волны.
        if (bloom_evt > 0.001) {
                float wv = sin((1.0 - y) * 9.0 - time_s * 1.6);
                wv = pow(max(wv, 0.0), 3.0) * (0.35 + 0.65 * (1.0 - y));
                col += vec3(0.10, 0.50, 0.42) * wv * bloom_evt * 0.5;
        }

        // Дно: тёмный силуэт с неровным рельефом.
        float bot = smoothstep(0.86, 1.0, y + fbm(vec2(UV.x * 6.0, 3.7)) * 0.05);
        col = mix(col, vec3(0.004, 0.008, 0.018), bot * 0.8);

        // Рельеф бездны: трассировка луча по SDF со smooth CSG и туманом
        // по глубине. Свет игрока достаёт и сюда — склоны подсвечиваются,
        // дальние холмы тонут в толще воды.
        float rmask = smoothstep(0.56, 0.72, y);
        if (rmask > 0.002) {
                vec3 ro = vec3(screen_px.x * 0.5 + sway.x * 2.0 + sin(time_s * 0.05) * 26.0,
                                screen_px.y * 0.42 + sway.y,
                                -260.0);
                vec3 pl = vec3(px.x, screen_px.y - px.y, 0.0);
                vec3 rd = normalize(pl - ro);
                float tt = 0.0;
                float hit = 1e5;
                vec4 sd = vec4(0.0);
                for (int step_i = 0; step_i < 30; step_i++) {
                        vec3 sp = ro + rd * tt;
                        sd = map_abyss(sp, time_s);
                        if (sd.w < 1.0) {
                                hit = tt;
                                break;
                        }
                        tt += max(sd.w * 0.85, 2.0);
                        if (tt > 1150.0) {
                                break;
                        }
                }
                if (hit < 1e5) {
                        vec3 hp = ro + rd * hit;
                        vec3 n = abyss_normal(hp, time_s);
                        vec3 lw = vec3(light_pos.x, screen_px.y - light_pos.y, 240.0);
                        vec3 ld = lw - hp;
                        float dl = max(length(ld), 1.0);
                        ld /= dl;
                        float ndl = clamp(dot(n, ld), 0.0, 1.0);
                        float att = exp(-dl / 640.0) * light_i;
                        float rim = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);
                        vec3 albedo = map_abyss(hp, time_s).rgb;
                        vec3 base = albedo * (0.35 + 0.85 * ndl * (0.35 + 0.65 * att));
                        base += vec3(0.30, 0.72, 0.66) * rim * (0.16 + 0.5 * att);
                        vec3 water = mix(vec3(0.014, 0.045, 0.095), vec3(0.006, 0.012, 0.028), clamp((hp.y + 200.0) / 300.0, 0.0, 1.0));
                        float fog = exp(-hit * 0.0034);
                        vec3 rel = mix(water, base, fog);
                        col = mix(col, rel, rmask * 0.9);
                }
        }

        // Свет игрока — три мягких мазка разного радиуса.
        vec2 dpx = px - light_pos;
        float d = length(dpx);
        float g1 = exp(-d / max(light_r * 1.6, 1.0));
        float g2 = exp(-d / max(light_r * 0.55, 1.0));
        float g3 = exp(-d / max(light_r * 0.16, 1.0));
        col += vec3(0.62, 0.95, 0.88) * (g1 * 0.30 + g2 * 0.26) * light_i;
        col += vec3(0.92, 1.0, 0.97) * g3 * 0.22 * light_i;

        // Метаболы: там, где световые массы сближаются, между ними всплывает
        // светящаяся плёнка-перемычка — тела плавно перетекают друг в друга.
        if (balls_n > 0) {
                vec4 bf = ball_field(px);
                float film = exp(-abs(bf.w) / max(balls_k * 0.45, 1.0));
                float halo = exp(-max(bf.w, 0.0) / max(balls_k * 1.7, 1.0));
                vec3 bcol = bf.rgb * (0.45 + 0.55 * light_i);
                col += bcol * (film * 0.32 + halo * 0.12);
        }

        // Виньетка и тонкое зерно — фактура живописи.
        vec2 q = UV - 0.5;
        col *= 1.0 - dot(q, q) * 0.55;
        float gr = hash21(px + vec2(fract(time_s * 13.7) * 100.0));
        col += (gr - 0.5) * 0.02;

        COLOR = vec4(col, 1.0);
}
