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
// Alpha 0 is the cleared value: nothing was drawn there
float unpack_shadow_depth0(float alpha) { return alpha == 0.0 ? 1.0 : alpha; }
#define read_shadow_depth0(texel)                                              \
    unpack_shadow_depth0(texelFetch(shadowcolor0, texel, 0).a)
#else
#define read_shadow_depth0(texel) texelFetch(shadowtex0, texel, 0).x
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
