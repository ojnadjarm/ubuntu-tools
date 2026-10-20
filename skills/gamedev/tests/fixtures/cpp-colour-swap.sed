# Swaps the red and blue base colour channels in the template's shaders/mesh.frag: builds and validates clean, the golden ꟻLIP stage must fail.
s/vec3 base = texture(base_color_map, in_uv)\.rgb \* mat\.base_color_factor\.rgb;/vec3 base = (texture(base_color_map, in_uv).rgb * mat.base_color_factor.rgb).bgr;/
