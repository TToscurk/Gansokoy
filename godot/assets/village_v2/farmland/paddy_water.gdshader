shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

varying vec2 surface_xz;

void vertex() {
    surface_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Opaque, silt-rich shallow water: sky tint strengthens at grazing angles.
// Small broken highlights avoid transparent full-field sheets and their sorting stripes.
void fragment() {
    float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
    float silt = clamp(COLOR.r, 0.0, 1.0);
    float wave = sin(surface_xz.x * 2.1 + sin(surface_xz.y * 0.87)) * sin(surface_xz.y * 3.8 - surface_xz.x * 0.49);
    float sparkle = smoothstep(0.85, 0.98, wave) * (0.018 + grazing * 0.15);
    vec3 mud = mix(vec3(0.17, 0.16, 0.105), vec3(0.28, 0.27, 0.19), silt);
    vec3 sky = vec3(0.39, 0.48, 0.50);
    ALBEDO = mix(mud, sky, 0.26 + grazing * 0.74) + vec3(sparkle);
    ROUGHNESS = mix(0.32, 0.10, grazing);
    SPECULAR = 0.88;
}
