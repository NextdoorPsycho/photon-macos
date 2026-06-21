#ifndef INCLUDE_LIGHTING_HANDHELD_LIGHTING
#define INCLUDE_LIGHTING_HANDHELD_LIGHTING

#ifdef COLORED_LIGHTS
uniform sampler2D light_data_sampler;
#endif

#ifdef IS_IRIS
uniform vec3 relativeEyePosition;
#endif

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

#if defined MC_OS_MAC && !defined COLORED_LIGHTS
vec3 get_handheld_emitter_color(int held_item_id) {
    switch (held_item_id) {
        case 10032:
            return vec3(1.00, 1.00, 1.00) * 12.0; // Strong white light
        case 10033:
            return vec3(1.00, 1.00, 1.00) * 6.0; // Medium white light
        case 10034:
            return vec3(1.00, 1.00, 1.00) * 1.0; // Weak white light
        case 10035:
            return vec3(1.00, 0.55, 0.27) * 14.0; // Strong golden light
        case 10036:
            return vec3(1.00, 0.57, 0.30) * 8.0; // Medium golden light
        case 10037:
            return vec3(1.00, 0.57, 0.30) * 6.0; // Weak golden light
        case 10038:
            return vec3(1.00, 0.18, 0.10) * 5.0; // Redstone components
        case 10039:
            return vec3(1.00, 0.38, 0.10) * 7.0; // Lava
        case 10040:
            return vec3(1.00, 0.45, 0.10) * 9.0; // Medium orange light
        case 10041:
            return vec3(1.00, 0.63, 0.15) * 4.0; // Brewing stand
        case 10042:
            return vec3(1.00, 0.57, 0.30) * 12.0; // Jack o'Lantern
        case 10043:
            return vec3(0.45, 0.73, 1.00) * 6.0; // Soul lights
        case 10044:
            return vec3(0.45, 0.73, 1.00) * 14.0; // Beacon
        case 10045:
            return vec3(0.75, 1.00, 0.83) * 3.0; // End portal frame
        case 10046:
            return vec3(0.75, 1.00, 0.83) * 1.0; // Sculk
        case 10047:
            return vec3(0.60, 0.10, 1.00) * 2.5; // Pink glow
        case 10048:
            return vec3(0.75, 1.00, 0.50) * 1.0; // Sea pickle
        case 10049:
            return vec3(1.00, 0.50, 0.25) * 4.0; // Nether plants
        case 10050:
            return vec3(1.00, 0.57, 0.30) * 8.0; // Candles
        case 10051:
            return vec3(1.00, 0.65, 0.30) * 8.0; // Ochre froglight
        case 10052:
            return vec3(0.86, 1.00, 0.44) * 8.0; // Verdant froglight
        case 10053:
            return vec3(0.75, 0.44, 1.00) * 8.0; // Pearlescent froglight
        case 10054:
            return vec3(0.60, 0.10, 1.00) * 2.0; // Enchanting table
        case 10055:
            return vec3(0.75, 0.44, 1.00) * 4.0; // Amethyst cluster
        case 10056:
            return vec3(0.75, 0.44, 1.00) * 4.0; // Calibrated sculk sensor
        case 10057:
            return vec3(0.75, 1.00, 0.83) * 6.0; // Active sculk sensor
        case 10058:
            return vec3(1.00, 0.18, 0.10) * 3.3; // Redstone block
        case 10059:
            return vec3(1.00, 0.50, 0.25) * 3.0; // Open eyeblossom
        case 10060:
            return vec3(0.85, 1.30, 1.00) * 3.9; // Copper torch and lanterns
        case 10061:
            return vec3(1.00, 0.57, 0.30) * 8.0; // Copper bulbs
        case 10062:
            return vec3(0.60, 0.10, 1.00) * 12.0; // Nether portal
    }

    return vec3(0.0);
}
#endif

vec3 get_handheld_light_color(int held_item_id, int held_item_light_value) {
#ifdef COLORED_LIGHTS
    bool is_emitter = 10032 <= held_item_id && held_item_id < 10064;

    if (is_emitter) {
        return texelFetch(
                   light_data_sampler,
                   ivec2(int(held_item_id) - 10032, 0),
                   0
        )
            .rgb;
    } else {
        return vec3(0.0);
    }
#elif defined MC_OS_MAC
    vec3 emitter_color = get_handheld_emitter_color(held_item_id);
    if (max_of(emitter_color) > 0.0) {
        return emitter_color;
    }

    return (blocklight_color * blocklight_scale * rcp(15.0))
        * held_item_light_value;
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

    vec3 light_color = max(
        get_handheld_light_color(heldItemId, heldBlockLightValue),
        get_handheld_light_color(heldItemId2, heldBlockLightValue2)
    );

    float falloff = get_handheld_light_falloff(scene_pos, ao);

    return light_color * falloff;
}

#endif // INCLUDE_LIGHTING_HANDHELD_LIGHTING
