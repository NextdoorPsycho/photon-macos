/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/lpv/floodfill.fsh:
  Floodfill iteration for the atlas path (no compute shaders). Each fragment of
  the light atlas is one voxel, apart from the rows that hold the cloud shadow
  map copy. The math mirrors update_lpv() in
  include/lighting/lpv/floodfill.glsl and has to be kept in step with it.
  Alpha remembers the voxel's block ID for a few frames, because the shadow
  pass only writes part of the voxel atlas on any one frame

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 light_out;

/* RENDERTARGETS: 17 */

uniform sampler2D colortex17; // light atlas, previous frame
uniform sampler2D shadowcolor1; // voxel atlas, this frame

#if defined WORLD_OVERWORLD
uniform sampler2D colortex8; // cloud shadow map
#endif

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform int frameCounter;

#include "/include/lighting/lpv/atlas.glsl"
#include "/include/lighting/lpv/light_colors.glsl"

bool is_emitter(uint block_id) { return 32u <= block_id && block_id < 80u; }

bool is_translucent(uint block_id) { return 81u <= block_id && block_id < 97u; }

vec3 get_emitted_light(uint block_id) {
    return is_emitter(block_id) ? light_color[block_id - 32u] : vec3(0.0);
}

vec3 get_tint(uint block_id, bool is_transparent) {
    return is_translucent(block_id)
        ? tint_color[block_id - 81u]
        : vec3(is_transparent);
}

ivec3 clamp_to_voxel_volume(ivec3 pos) {
    return clamp(pos, ivec3(0), voxel_volume_size - 1);
}

// Age at which a remembered voxel is dropped, see main(). The Nether voxelizes
// everything on every frame. Half floats hold ID + 256 * age exactly up to 7
#if defined WORLD_NETHER
const uint voxel_memory_age = 1u;
#else
const uint voxel_memory_age = 6u;
#endif

// Light and voxel memory at `pos` in last frame's atlas
vec4 read_previous(ivec3 pos) {
    if (clamp_to_voxel_volume(pos) != pos) {
        return vec4(0.0);
    }

    return texelFetch(
        colortex17,
        light_atlas_origin + voxel_to_atlas(pos, light_atlas_tiles_x),
        0
    );
}

vec3 gather_light(ivec3 pos, vec3 center_light) {
    const ivec3[6] face_offsets = ivec3[6](
        ivec3(1, 0, 0),
        ivec3(0, 1, 0),
        ivec3(0, 0, 1),
        ivec3(-1, 0, 0),
        ivec3(0, -1, 0),
        ivec3(0, 0, -1)
    );

    if (clamp_to_voxel_volume(pos) != pos) {
        return vec3(0.0);
    }

    const float center_weight = 1.05;

    vec3 light = center_light * center_weight;

    for (int i = 0; i < 6; ++i) {
        light += read_light_atlas(
            colortex17,
            clamp_to_voxel_volume(pos + face_offsets[i])
        );
    }

    return light * rcp(7.0 * center_weight);
}

void main() {
    vec3 current_center
        = get_voxel_volume_center(gbufferModelViewInverse[2].xyz);
    vec3 previous_center = get_voxel_volume_center(vec3(
        gbufferPreviousModelView[0].z,
        gbufferPreviousModelView[1].z,
        gbufferPreviousModelView[2].z
    ));

    ivec2 texel = ivec2(gl_FragCoord.xy);

    // Rows below the light tiles: copy of the cloud shadow map
    if (texel.y < light_atlas_cloud_rows) {
#if defined WORLD_OVERWORLD
        light_out = vec4(texelFetch(colortex8, min(texel, ivec2(511)), 0).rgb, 0.0);
#else
        light_out = vec4(1.0, 1.0, 1.0, 0.0);
#endif
        return;
    }

    // Texels past the tiles, when a small shadow map caps the volume size
    if (any(greaterThanEqual(
            texel - light_atlas_origin,
            light_atlas_tiles_size
        ))) {
        light_out = vec4(0.0);
        return;
    }

    ivec3 pos = atlas_to_voxel(texel - light_atlas_origin, light_atlas_tiles_x);
    ivec3 previous_pos = ivec3(
        vec3(pos) - floor(previousCameraPosition) + floor(cameraPosition)
        - current_center + previous_center
    );

    vec4 previous = read_previous(previous_pos);

    // Voxel memory: ID + 256 * age. The age counts up every fourth frame (on
    // half the counter, like voxel_frame()) and
    // an entry is dropped at voxel_memory_age, well after the shadow pass
    // should have written the block again. Nothing here depends on which
    // frame of the cycle this is. A lower ID in memory stays: that is the full
    // block variant, seen from a face that is voxelized on the other frame
    uint block_id = read_voxel_atlas(shadowcolor1, pos);
    // The texture starts out with whatever was in memory
    uint memory = uint(clamp(previous.a, 0.0, 2047.0) + 0.5);
    uint memory_id = memory & 255u;
    uint age = (memory >> 8) + uint(((frameCounter >> 1) & 3) == 0);

    if (age >= voxel_memory_age) {
        memory_id = 0u;
    }

    if (block_id == 0u || (memory_id != 0u && memory_id < block_id)) {
        block_id = memory_id;
    } else {
        age = 0u;
    }

    light_out.a = block_id == 0u ? 0.0 : float(block_id + 256u * age);

    bool transparent = block_id == 0u || block_id >= 128u;
    block_id = block_id & 127u;

    vec3 light_avg = gather_light(previous_pos, previous.rgb);
    vec3 emitted_light = sqr(get_emitted_light(block_id));
    vec3 tint = sqr(get_tint(block_id, transparent));

    light_out.rgb = emitted_light + light_avg * tint;
}

#ifndef PHOTON_LPV_ATLAS
#error "This program should be disabled unless colored lights use the atlas path"
#endif
