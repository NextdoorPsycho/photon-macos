/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/d0_sky_map:
  Render omnidirectional sky map for reflections and SH lighting

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

#if defined WORLD_OVERWORLD && defined PROGRAM_DEFERRED0 && defined SH_SKYLIGHT && !defined PHOTON_HAS_COMPUTE
#define PHOTON_SKY_SH_FRAGMENT_FALLBACK
#endif

layout(location = 0) out vec3 sky_map;

/* RENDERTARGETS: 4 */

in vec2 uv;

flat in vec3 ambient_color;
flat in vec3 light_color;

#if defined WORLD_OVERWORLD
flat in vec3 sun_color;
flat in vec3 moon_color;
flat in vec3 sky_color;

flat in float aurora_amount;
flat in mat2x3 aurora_colors;

flat in float rainbow_amount;

#include "/include/sky/clouds/parameters.glsl"
flat in CloudsParameters clouds_params;

#include "/include/fog/overworld/parameters.glsl"
flat in OverworldFogParameters fog_params;
#endif

// ------------
//   Uniforms
// ------------

uniform sampler3D colortex6; // 3D bubbly worley noise
#define SAMPLER_WORLEY_BUBBLY colortex6
uniform sampler3D colortex7; // 3D swirley worley noise
#define SAMPLER_WORLEY_SWIRLEY colortex7

#if defined WORLD_OVERWORLD && defined GALAXY
uniform sampler2D colortex13;
#define galaxy_sampler colortex13
#endif

uniform sampler3D depthtex0; // atmospheric scattering LUT
uniform sampler2D depthtex1;

uniform sampler2D colortex8; // cloud shadow map

uniform sampler2D noisetex;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;

uniform int worldTime;
uniform int moonPhase;
uniform float sunAngle;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform int isEyeInWater;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float blindness;
uniform float darknessFactor;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform vec2 view_res;
uniform vec2 view_pixel_size;
uniform vec2 taa_offset;

uniform float world_age;
uniform float eye_skylight;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float biome_cave;
uniform float biome_may_snow;

// ------------
//   Includes
// ------------

#define ATMOSPHERE_SCATTERING_LUT depthtex0
#define CLOUDS_USE_LOCAL_COVERAGE_MAP

#ifdef CLOUDS_CUMULUS_PRECOMPUTE_LOCAL_COVERAGE
#define CLOUDS_USE_LOCAL_COVERAGE_MAP
#endif

#if defined WORLD_OVERWORLD
#include "/include/fog/overworld/analytic.glsl"
#include "/include/sky/aurora.glsl"
#endif

#include "/include/sky/projection.glsl"
#include "/include/sky/sky.glsl"

#ifdef PHOTON_SKY_SH_FRAGMENT_FALLBACK
#include "/include/utility/sampling.glsl"

// Native macOS cannot run Photon's compute SH reduction. Approximate the same
// colortex4 SH rows from a tiny number of sky-map fragments instead.
const int photon_sky_sh_fallback_samples = 64;

float photon_sky_sh_coeff(int band, vec3 direction) {
    float x = direction.x;
    float y = direction.y;
    float z = direction.z;

    switch (band) {
        case 0:
            return 0.2820947918;
        case 1:
            return 0.4886025119 * x;
        case 2:
            return 0.4886025119 * z;
        case 3:
            return 0.4886025119 * y;
        case 4:
            return 1.0925484310 * x * y;
        case 5:
            return 1.0925484310 * y * z;
        case 6:
            return 0.3153915653 * (3.0 * z * z - 1.0);
        case 7:
            return 0.7725484040 * x * z;
        case 8:
            return 0.3862742020 * (x * x - y * y);
    }

    return 0.0;
}

vec3 photon_draw_sky_for_sh(vec3 ray_dir) {
    vec3 result = draw_sky(ray_dir);

#if defined WORLD_OVERWORLD
    mat2x3 fog = air_fog_analytic(
        cameraPosition,
        cameraPosition + ray_dir,
        true,
        eye_skylight,
        1.0
    );
    result = result * fog[1] + fog[0];
#endif

    return result;
}

vec3 photon_generate_sky_sh_band(int band) {
    vec3 sum = vec3(0.0);
    float skylight_boost = get_skylight_boost();

    for (int i = 0; i < photon_sky_sh_fallback_samples; ++i) {
        vec3 direction = uniform_hemisphere_sample(vec3(0.0, 1.0, 0.0), r2(i));
        vec3 radiance = photon_draw_sky_for_sh(direction) * skylight_boost;
        sum += radiance * photon_sky_sh_coeff(band, direction);
    }

    return sum * (tau / float(photon_sky_sh_fallback_samples));
}

vec3 photon_generate_sky_irradiance_up() {
    vec3 sum = vec3(0.0);
    float skylight_boost = get_skylight_boost();

    for (int i = 0; i < photon_sky_sh_fallback_samples; ++i) {
        vec3 direction = uniform_hemisphere_sample(vec3(0.0, 1.0, 0.0), r2(i));
        vec3 radiance = photon_draw_sky_for_sh(direction) * skylight_boost;
        sum += radiance * max0(direction.y);
    }

    return sum * (tau / float(photon_sky_sh_fallback_samples));
}
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    if (texel.x == sky_map_res.x) { // Store lighting colors
        sky_map = vec3(0.0);
        switch (texel.y) {
            case 0:
                sky_map = light_color;
                break;

            case 1:
                sky_map = ambient_color;
                break;

#ifdef PHOTON_SKY_SH_FRAGMENT_FALLBACK
            case 2:
                sky_map = photon_generate_sky_sh_band(0);
                break;

            case 3:
                sky_map = photon_generate_sky_sh_band(1);
                break;

            case 4:
                sky_map = photon_generate_sky_sh_band(2);
                break;

            case 5:
                sky_map = photon_generate_sky_sh_band(3);
                break;

            case 6:
                sky_map = photon_generate_sky_sh_band(4);
                break;

            case 7:
                sky_map = photon_generate_sky_sh_band(5);
                break;

            case 8:
                sky_map = photon_generate_sky_sh_band(6);
                break;

            case 9:
                sky_map = photon_generate_sky_sh_band(7);
                break;

            case 10:
                sky_map = photon_generate_sky_sh_band(8);
                break;

            case 11:
                sky_map = photon_generate_sky_irradiance_up();
                break;
#endif
        }
    } else { // Draw sky map
        vec3 ray_dir = unproject_sky(uv);

        sky_map = draw_sky(ray_dir);

#if defined WORLD_OVERWORLD
        // Apply analytic fog over sky
        mat2x3 fog = air_fog_analytic(
            cameraPosition,
            cameraPosition + ray_dir,
            true,
            eye_skylight,
            1.0
        );
        sky_map = sky_map * fog[1] + fog[0];
#endif
    }
}
