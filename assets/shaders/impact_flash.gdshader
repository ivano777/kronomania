// Impact flash — mixes the sprite toward pure white by flash_amount.
// Modulate (COLOR) is applied after the mix so the dim/gray presentation
// tints still work; at flash_amount 0 this is identical to the default pipeline.
shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	tex.rgb = mix(tex.rgb, vec3(1.0), flash_amount);
	COLOR = tex * COLOR;
}
