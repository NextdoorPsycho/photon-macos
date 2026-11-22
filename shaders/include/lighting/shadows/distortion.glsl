#if !defined INCLUDE_LIGHTING_DISTORTION
#define INCLUDE_LIGHTING_DISTORTION

#include "/include/utility/fast_math.glsl"

// Euclidian distance is defined as sqrt(a^2 + b^2 + ...). This function instead
// does quartic_root(a^4 + b^4 + ...). This results in smaller distances along
// the diagonal axes
// On the atlas path (see lpv/atlas.glsl) the right-hand strip of the shadow map
// holds the voxel atlas, and the shadow projection only fills the square
// region to its left. Shadow UVs keep meaning "0 to 1 across the projection":
// texel lookups multiply by shadow_region_res, filtered lookups by
// shadow_region_scale
#ifdef PHOTON_LPV_ATLAS
#include "/include/lighting/lpv/atlas_size.glsl"

const int shadow_region_res = shadowMapResolution - 8 * lpv_atlas_n;
#else
const int shadow_region_res = shadowMapResolution;
#endif
const float shadow_region_scale
    = float(shadow_region_res) / float(shadowMapResolution);

// Depth of the nearest shadow caster, translucent ones included. Programs
// that undefine SHADOW_COLOR have no shadowcolor0 and keep using shadowtex0
#if defined PHOTON_SHADOW_DEPTH0_IN_COLOR && defined SHADOW_COLOR
// Tint and depth share an RGBA8 texel: an RGBA16 one costs twice as much to
// clear and store, every frame. One 32 bit word, most significant byte in red:
//
//   14 bits  depth, 1 to 16383 across the range the shadow projection uses
//            (SHADOW_DEPTH_SCALE of the depth buffer), finer than 16 bits
//            across all of it. 0 is the cleared value: nothing was drawn
//    6 bits  per tint channel, square root encoded. Dithered in the shadow
//            pass, so filtering and TAA average to the exact tint. 0 stays 0
//            (opaque) and anything else stays above it
const float shadow_packed_depth_min = 0.5 - 0.5 * SHADOW_DEPTH_SCALE;
const float shadow_packed_depth_range = SHADOW_DEPTH_SCALE;

// Largest tint stored. White is 0.25, water caustics reach four times that
#ifdef WATER_CAUSTICS
const float shadow_packed_tint_max = 1.0;
#else
const float shadow_packed_tint_max = 0.25;
#endif

vec4 pack_shadow_color_depth(vec3 color, float depth, float dither) {
    vec3 encoded = sqrt(clamp01(color / shadow_packed_tint_max));
    uvec3 tint
        = uvec3(encoded * 63.0 + fract(dither + vec3(0.0, 1.0, 2.0) / 3.0));
    tint = clamp(tint, uvec3(greaterThan(color, vec3(0.0))), uvec3(63u));

    float depth_fraction
        = clamp01((depth - shadow_packed_depth_min) / shadow_packed_depth_range);
    uint word = (1u + uint(depth_fraction * 16382.0 + 0.5)) << 18
        | tint.r << 12 | tint.g << 6 | tint.b;

    return vec4((uvec4(word) >> uvec4(24u, 16u, 8u, 0u)) & 255u) * rcp(255.0);
}

// rgb: tint as the shadow pass wrote it, a: depth of the nearest caster
vec4 unpack_shadow_color_depth(vec4 texel) {
    uvec4 bytes = uvec4(texel * 255.0 + 0.5);
    uint word = bytes.r << 24 | bytes.g << 16 | bytes.b << 8 | bytes.a;
    uint depth = word >> 18;
    vec3 encoded
        = vec3((uvec3(word) >> uvec3(12u, 6u, 0u)) & 63u) * rcp(63.0);

    return vec4(
        shadow_packed_tint_max * encoded * encoded,
        depth == 0u
            ? 1.0
            : shadow_packed_depth_min
                + float(depth - 1u) * (shadow_packed_depth_range / 16382.0)
    );
}

#define read_shadow_depth0(texel)                                              \
    unpack_shadow_color_depth(texelFetch(shadowcolor0, texel, 0)).a
#define read_shadow_color0(texel)                                              \
    unpack_shadow_color_depth(texelFetch(shadowcolor0, texel, 0)).rgb
#else
#define read_shadow_depth0(texel) texelFetch(shadowtex0, texel, 0).x
#define read_shadow_color0(texel) texelFetch(shadowcolor0, texel, 0).rgb
#endif

// Moves clip-space XY from the whole shadow map into the shadow region
vec2 shadow_clip_to_region(vec2 shadow_clip_pos) {
    return shadow_clip_pos * shadow_region_scale + (shadow_region_scale - 1.0);
}

float quartic_length(vec2 v) { return sqrt(sqrt(pow4(v.x) + pow4(v.y))); }

float get_distortion_factor(vec2 shadow_clip_pos) {
    return quartic_length(shadow_clip_pos) * SHADOW_DISTORTION
        + (1.0 - SHADOW_DISTORTION);
}

vec3 distort_shadow_space(vec3 shadow_clip_pos, float distortion_factor) {
    return shadow_clip_pos
        * vec3(vec2(rcp(distortion_factor)), SHADOW_DEPTH_SCALE);
}

vec3 distort_shadow_space(vec3 shadow_clip_pos) {
    float distortion_factor = get_distortion_factor(shadow_clip_pos.xy);
    return distort_shadow_space(shadow_clip_pos, distortion_factor);
}

vec3 undistort_shadow_space(vec3 shadow_clip_pos) {
    shadow_clip_pos.xy *= (1.0 - SHADOW_DISTORTION)
        / (1.0 - quartic_length(shadow_clip_pos.xy));
    shadow_clip_pos.z *= rcp(SHADOW_DEPTH_SCALE);
    return shadow_clip_pos;
}

// Shadow bias method from Complementary Reimagined by Emin
// Many thanks to Emin for letting me use it <3
// https://www.complementary.dev/reimagined
vec3 get_shadow_bias(vec3 scene_pos, vec3 normal, float NoL, float skylight) {
#if defined WORLD_END
    skylight = 1.0;
#endif

    // Shadow bias without peter-panning
    return 0.25 * normal * clamp01(0.12 + 0.01 * length(scene_pos))
        * (2.0 - clamp01(NoL));
}

#endif // INCLUDE_LIGHTING_DISTORTION
