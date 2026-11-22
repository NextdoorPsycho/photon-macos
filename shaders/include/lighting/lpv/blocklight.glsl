#if !defined INCLUDE_LIGHTING_LPV_BLOCKLIGHT
#define INCLUDE_LIGHTING_LPV_BLOCKLIGHT

#include "voxelization.glsl"

#if defined PHOTON_LPV_ATLAS && COLORED_LIGHTS_SHADOWS > 0
#include "/include/utility/dithering.glsl"
#include "/include/utility/random.glsl"
#endif

#ifdef PHOTON_LPV_ATLAS
#include "atlas.glsl"

vec3 read_lpv_linear(vec3 pos) {
    return sample_light_atlas(light_atlas_sampler, pos);
}
#else
vec3 read_lpv_linear(vec3 pos) {
    if ((frameCounter & 1) == 0) {
        return texture(light_sampler_a, pos).rgb;
    } else {
        return texture(light_sampler_b, pos).rgb;
    }
}
#endif

#if defined PHOTON_LPV_ATLAS && COLORED_LIGHTS_SHADOWS > 0 && !defined NO_NORMAL
// Share of the light that reaches a surface directly: 0 when the surface faces
// away from the light source that lights its voxel, or when a ray to that
// source through the voxel volume hits a full block. The ray aims at a
// different point of the source on every frame, which gives a penumbra once
// the frames are blended. Returns 1 where no source is known
float get_lpv_light_visibility(vec3 voxel_pos, vec3 normal) {
    const int max_steps = 28;
    // Size of the light inside its block
    const float source_size = 0.6;

    vec3 origin = voxel_pos + normal * 0.05;
    ivec3 cell = ivec3(floor(voxel_pos + normal * 0.5));

    vec4 source = texelFetch(
        light_atlas_sampler,
        light_atlas_source_origin + voxel_to_atlas(cell, light_atlas_tiles_x),
        0
    );

    if (source.a < 0.5) {
        return 1.0;
    }

    ivec3 source_cell = cell + ivec3(round(source.xyz));

    if (clamp(source_cell, ivec3(0), voxel_volume_size - 1) != source_cell) {
        return 1.0;
    }

    // The offset is stale while lights change: it has to end at a light
    uint source_id = uint(
        clamp(
            abs(texelFetch(
                    light_atlas_sampler,
                    light_atlas_origin
                        + voxel_to_atlas(source_cell, light_atlas_tiles_x),
                    0
            )
                    .a),
            0.0,
            2047.0
        )
        + 0.5
    ) & 255u;

    if ((source_id & 127u) < 32u || (source_id & 127u) >= 80u) {
        return 1.0;
    }

    float dither = interleaved_gradient_noise(gl_FragCoord.xy, frameCounter);
    vec3 jitter = (r3(frameCounter, vec3(dither)) - 0.5) * source_size;

    // A small source shines from the middle of its block. A full block shines
    // from its faces, so aim at the nearest point of the cube: a lamp set
    // into a floor still lights that floor, along the surface
    vec3 target = source_id >= 128u
        ? vec3(source_cell) + 0.5 + jitter
        : clamp(origin + jitter, vec3(source_cell), vec3(source_cell) + 1.0);
    float near_start = source_id >= 128u ? 0.7 : 0.1;

    vec3 ray = target - origin;
    float ray_length = max(length(ray), 1e-3);
    vec3 ray_dir = ray / ray_length;

    // Only surfaces turned away darken: the propagated light already falls
    // off with distance, and a floor far from a light sees it at a low angle.
    // Not on the faces of the source itself and of the blocks touching it
    float facing = linear_step(-0.3, -0.05, dot(normal, ray_dir));
    facing = mix(
        1.0,
        facing,
        linear_step(near_start, near_start + 0.8, ray_length)
    );
    // Block faces only. Particles and plants are flat cards whose normal says
    // nothing about the shape they stand for
    facing = max_of(abs(normal)) > 0.99 ? facing : 1.0;

    if (facing <= 0.0) {
        return 0.0;
    }

    // Walk the voxels along the ray
    cell = ivec3(floor(origin));
    vec3 step_dir = vec3(greaterThanEqual(ray_dir, vec3(0.0))) * 2.0 - 1.0;
    vec3 step_length = 1.0 / max(abs(ray_dir), 1e-4);
    vec3 next = (vec3(cell) + max(step_dir, 0.0) - origin) * step_dir
        * step_length;

    for (int i = 0; i < max_steps; ++i) {
        vec3 axis = vec3(lessThanEqual(next.xyz, min(next.yzx, next.zxy)));

        if (min_of(next) >= ray_length) {
            break;
        }

        cell += ivec3(axis * step_dir);
        next += axis * step_length;

        if (cell == source_cell
            || clamp(cell, ivec3(0), voxel_volume_size - 1) != cell) {
            break;
        }

        uint block_id = uint(
            clamp(
                abs(texelFetch(
                        light_atlas_sampler,
                        light_atlas_origin
                            + voxel_to_atlas(cell, light_atlas_tiles_x),
                        0
                )
                        .a),
                0.0,
                2047.0
            )
            + 0.5
        ) & 255u;

        // Full blocks other than tinted glass
        if (block_id != 0u && block_id < 128u
            && (block_id < 81u || block_id >= 97u)) {
            return 0.0;
        }
    }

    return facing;
}
#endif

float lpv_distance_fade(vec3 scene_pos) {
    float distance_fade
        = 2.0 * max_of(abs(scene_pos / vec3(voxel_volume_size)));
    distance_fade = linear_step(0.75, 1.0, distance_fade);

    return distance_fade;
}

vec3 get_lpv_blocklight(
    vec3 scene_pos,
    vec3 normal,
    vec3 mc_blocklight,
    float ao,
    float daylight
) {
    vec3 voxel_pos = scene_to_voxel_space(scene_pos);

    if (is_inside_voxel_volume(voxel_pos)) {
#ifndef NO_NORMAL
        vec3 sample_pos
            = clamp01((voxel_pos + normal * 0.5) / vec3(voxel_volume_size));
        // Full ambient occlusion draws dark joins where a wall meets the
        // floor right beside a light
        vec3 lpv_blocklight = sqrt(read_lpv_linear(sample_pos))
            * mix(1.0, ao, 0.01 * float(COLORED_LIGHTS_AO));
#else
        vec3 sample_pos = clamp01(voxel_pos / vec3(voxel_volume_size));
        vec3 lpv_blocklight = sqrt(read_lpv_linear(sample_pos));
#endif

#if COLORED_LIGHTS_DAYLIGHT_BOOST > 0
        // In daylight the long dim tail of a light only tints everything
        // around it. Brighten what is near the source and let the tail drop
        // away, so the light reads as a pool. Levels around daylight_knee
        // keep their brightness
        const float daylight_boost = float(COLORED_LIGHTS_DAYLIGHT_BOOST);
        const float daylight_knee = 0.75;
        float level = max_of(lpv_blocklight);
        lpv_blocklight *= mix(
            1.0,
            daylight_boost * level
                / (level + (daylight_boost - 1.0) * daylight_knee),
            daylight
        );
#endif

        lpv_blocklight *= 1.25 * BLOCKLIGHT_I;

#ifdef COLORED_LIGHTS_VANILLA_LIGHTMAP_CONTRIBUTION
        float lpv_luminance = dot(lpv_blocklight, luminance_weights_rec2020);
        float vanilla_lightmap_contribution = exp2(-4.0 * lpv_luminance);
        vec3 lightmap_light = mc_blocklight;

#ifdef COLORED_LIGHTS_TINT_LIGHTMAP
        // The lightmap has one color for every light. Where it fills in
        // around a red or blue light it pulls the edge of the pool, and any
        // overlap of colors, towards that one color. Give it the hue the
        // volume holds there and keep its brightness. The limit on the
        // scale is for deep blue and red, which have little luminance
        lightmap_light = mix(
            lightmap_light,
            lpv_blocklight
                * (dot(lightmap_light, luminance_weights_rec2020)
                    / max(
                        max(lpv_luminance, 0.33 * max_of(lpv_blocklight)),
                        1e-4
                    )),
            linear_step(0.0, 0.02, lpv_luminance)
        );
#endif
#endif

#if defined PHOTON_LPV_ATLAS && COLORED_LIGHTS_SHADOWS > 0 && !defined NO_NORMAL
        // After the lightmap share is fixed, so that it does not fill the
        // shadow back in. What is left in shadow stands for bounced light
        if (max_of(lpv_blocklight) > 0.005) {
            lpv_blocklight *= mix(
                1.0 - 0.01 * float(COLORED_LIGHTS_SHADOWS),
                1.0,
                get_lpv_light_visibility(voxel_pos, normal)
            );
        }
#endif

#ifdef COLORED_LIGHTS_VANILLA_LIGHTMAP_CONTRIBUTION
#if COLORED_LIGHTS_VANILLA_LIGHTMAP_CONTRIBUTION_FALLOFF \
    == COLORED_LIGHTS_VANILLA_LIGHTMAP_CONTRIBUTION_FALLOFF_SQUARED
        lpv_blocklight
            += mix(vec3(dot(lightmap_light, luminance_weights_rec2020)),
                   lightmap_light,
                   0.5)
            * lightmap_light * 0.5 * vanilla_lightmap_contribution;
#else
        lpv_blocklight += lightmap_light * vanilla_lightmap_contribution;
#endif
#endif

        // Darkness effect
        float darkness_factor
            = mix(1.0,
                  dampen(abs(cos(2.0 * frameTimeCounter))) * 0.67 + 0.2,
                  darknessFactor)
                * 0.75
            + 0.25;
        lpv_blocklight *= darkness_factor;

        float distance_fade = lpv_distance_fade(scene_pos);

        return mix(lpv_blocklight, mc_blocklight, distance_fade);
    } else {
        return mc_blocklight;
    }
}

#endif // INCLUDE_LIGHTING_LPV_BLOCKLIGHT
