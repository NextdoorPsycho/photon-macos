#ifndef INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#ifdef PHOTON_LPV_ATLAS
// The table is included under another name: shading programs already have a
// `light_color` of their own
#define light_color lpv_light_color
#define tint_color lpv_tint_color
#include "/include/lighting/lpv/light_colors.glsl"
#undef light_color
#undef tint_color
#elif defined COLORED_LIGHTS
uniform sampler2D light_data_sampler;
#endif

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

vec3 get_handheld_light_color(int held_item_id, int held_item_light_value) {
#ifdef COLORED_LIGHTS
    bool is_emitter = 10032 <= held_item_id && held_item_id < 10080;

    if (is_emitter) {
#ifdef PHOTON_LPV_ATLAS
        return lpv_light_color[held_item_id - 10032];
#else
        return texelFetch(
                   light_data_sampler,
                   ivec2(int(held_item_id) - 10032, 0),
                   0
        )
            .rgb;
#endif
    } else {
        return vec3(0.0);
    }
#else
    return (blocklight_color * blocklight_scale * rcp(15.0))
        * held_item_light_value;
#endif
}

float get_handheld_light_falloff(vec3 scene_pos, float ao) {
    float falloff = lift(rcp(dot(scene_pos, scene_pos) + 1.0), 3.0);
    return falloff * mix(ao, 1.0, falloff * falloff)
        * HANDHELD_LIGHTING_INTENSITY;
}

vec3 get_handheld_lighting(vec3 scene_pos, float ao) {
#ifdef IS_IRIS
    // Center light on player rather than camera
    scene_pos += relativeEyePosition;
#endif

    // Sum the two hands so that two differently colored items both show
    vec3 handheld_color
        = get_handheld_light_color(heldItemId, heldBlockLightValue)
        + get_handheld_light_color(heldItemId2, heldBlockLightValue2);

    float falloff = get_handheld_light_falloff(scene_pos, ao);

    return handheld_color * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
