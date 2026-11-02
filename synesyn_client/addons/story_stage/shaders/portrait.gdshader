shader_type canvas_item;

uniform float blink = 0.0;
uniform float breath = 0.0;

void vertex() {
	VERTEX.y += sin(TIME * 1.6) * breath * 6.0 * UV.y;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	float band = smoothstep(0.18, 0.28, UV.y) * (1.0 - smoothstep(0.40, 0.50, UV.y));
	color.rgb *= 1.0 - blink * band;
	COLOR = color;
}
