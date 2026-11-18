shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.038;
uniform float vignette : hint_range(0.0, 1.0) = 0.62;
uniform float aberration : hint_range(0.0, 0.01) = 0.0022;
uniform float scanline : hint_range(0.0, 1.0) = 0.06;
uniform vec3 tint = vec3(0.94, 1.0, 1.045);
uniform float exposure = 0.92;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec2 cc = c * vec2(1.0, 0.96);
	float r = length(cc);
	vec2 dir = normalize(c + vec2(1e-6));
	vec2 off = dir * r * r * aberration;

	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	col *= exposure * tint;

	float vig = smoothstep(0.98, 0.30, r);
	col *= mix(1.0, vig, vignette);

	float sl = step(0.5, fract(uv.y * 180.0));
	col *= 1.0 - scanline * sl * 0.35;

	float n = hash(uv * 512.0 + vec2(TIME * 41.0, TIME * 19.0));
	col += (n - 0.5) * grain_amount;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
