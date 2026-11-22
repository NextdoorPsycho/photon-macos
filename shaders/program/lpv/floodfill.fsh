/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/lpv/floodfill.fsh:
  Floodfill iteration for the atlas path (no compute shaders). Each fragment of
  the light atlas is one voxel, apart from the rows that hold the cloud shadow
  map copy. The math mirrors update_lpv() in
  include/lighting/lpv/floodfill.glsl and has to be kept in step with it.
  Alpha remembers the voxel's block ID for a few frames, because the shadow
  pass only writes part of the voxel atlas on any one frame.
  Runs twice per frame (prepare1, then prepare2 with FLOODFILL_SECOND_PASS), so
  light spreads and fades two blocks per frame

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

layout(location = 0) out vec4 light_out;

/* RENDERTARGETS: 17 */

uniform sampler2D colortex17; // light atlas, previous frame
uniform sampler2D shadowcolor0; // voxel atlas in its right-hand strip, this frame

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
// everything on every frame. Half floats hold ID + 256 * age exactly up to 7.
// Small light sources use the age differently and go sooner
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
        vec3 neighbor_light = read_light_atlas(
            colortex17,
            clamp_to_voxel_volume(pos + face_offsets[i])
        );

#if COLORED_LIGHTS_BOUNCE > 0
        // A neighbor without any light is a solid block, which hands back
        // part of what reaches it. Unlit air ahead of the light does the same
        // for the few frames until it is reached
        if (max_of(neighbor_light) <= 0.0) {
            neighbor_light = center_light * (0.01 * float(COLORED_LIGHTS_BOUNCE));
        }
#endif

        light += neighbor_light;
    }

    return light * rcp(7.0 * center_weight);
}

#if COLORED_LIGHTS_SHADOWS > 0
// Offset from a voxel to the light source that lights it most, for the shadow
// rays in get_lpv_light_visibility(). A light source holds zero. Any other
// open voxel takes the offset of its brightest neighbor, one step longer:
// light only grows towards a source, so the steps add up to the vector to it.
// While lights change the offsets are stale, hence the length limit, and the
// lookup checks that the offset ends at a light source
vec4 update_light_source(ivec3 previous_pos) {
    const ivec3[6] face_offsets = ivec3[6](
        ivec3(1, 0, 0),
        ivec3(0, 1, 0),
        ivec3(0, 0, 1),
        ivec3(-1, 0, 0),
        ivec3(0, -1, 0),
        ivec3(0, 0, -1)
    );
    const float max_offset = 24.0;

    vec4 previous = read_previous(previous_pos);
    uint block_id = uint(clamp(abs(previous.a), 0.0, 2047.0) + 0.5) & 255u;

    if (is_emitter(block_id & 127u)) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    // Unlit voxels, which is most of the volume, and solid blocks
    if (max_of(previous.rgb) <= 0.0) {
        return vec4(0.0);
    }

    // The neighbor has to be brighter than this voxel. Where the light is
    // level (between two lights) rounding makes neighbors equal, and two
    // voxels that took each other's offset would keep an old one for good
    float brightest = max_of(previous.rgb);
    ivec3 brightest_offset = ivec3(0);

    for (int i = 0; i < 6; ++i) {
        float light = max_of(read_previous(previous_pos + face_offsets[i]).rgb);

        if (light > brightest) {
            brightest = light;
            brightest_offset = face_offsets[i];
        }
    }

    ivec3 neighbor_pos = previous_pos + brightest_offset;

    if (brightest_offset == ivec3(0)
        || clamp_to_voxel_volume(neighbor_pos) != neighbor_pos) {
        return vec4(0.0);
    }

    vec4 source = texelFetch(
        colortex17,
        light_atlas_source_origin
            + voxel_to_atlas(neighbor_pos, light_atlas_tiles_x),
        0
    );
    vec3 offset = source.xyz + vec3(brightest_offset);

    if (source.a < 0.5 || max_of(abs(offset)) > max_offset) {
        return vec4(0.0);
    }

    return vec4(offset, 1.0);
}
#endif

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
#if defined FLOODFILL_SECOND_PASS
        light_out = texelFetch(colortex17, texel, 0);
#elif defined WORLD_OVERWORLD
        light_out = vec4(texelFetch(colortex8, min(texel, ivec2(511)), 0).rgb, 0.0);
#else
        light_out = vec4(1.0, 1.0, 1.0, 0.0);
#endif
        return;
    }

#if COLORED_LIGHTS_SHADOWS > 0
    // Tiles above the light: offset to the light source
    ivec2 source_texel = texel - light_atlas_source_origin;

    if (source_texel.y >= 0
        && all(lessThan(source_texel, light_atlas_tiles_size))) {
#if defined FLOODFILL_SECOND_PASS
        // One update per frame is enough: the offsets only have to keep up
        // with lights being placed and removed
        light_out = texelFetch(colortex17, texel, 0);
#else
        ivec3 source_pos = ivec3(
            vec3(atlas_to_voxel(source_texel, light_atlas_tiles_x))
            - floor(previousCameraPosition) + floor(cameraPosition)
            - current_center + previous_center
        );
        light_out = update_light_source(source_pos);
#endif
        return;
    }
#endif

    // Texels past the tiles, when a small shadow map caps the volume size
    if (any(greaterThanEqual(
            texel - light_atlas_origin,
            light_atlas_tiles_size
        ))) {
        light_out = vec4(0.0);
        return;
    }

    ivec3 pos = atlas_to_voxel(texel - light_atlas_origin, light_atlas_tiles_x);
#if defined FLOODFILL_SECOND_PASS
    // Second iteration of the frame: the first has already moved the volume
    // with the camera and brought the voxel memory up to date
    vec4 previous = read_previous(pos);
    uint block_id = uint(clamp(abs(previous.a), 0.0, 2047.0) + 0.5) & 255u;

    light_out.a = previous.a;

    ivec3 previous_pos = pos;
#else
    ivec3 previous_pos = ivec3(
        vec3(pos) - floor(previousCameraPosition) + floor(cameraPosition)
        - current_center + previous_center
    );

    vec4 previous = read_previous(previous_pos);

    // Voxel memory: ID + 256 * age. The age counts up every fourth frame (on
    // half the counter, like voxel_frame()) and
    // an entry is dropped at voxel_memory_age, well after the shadow pass
    // should have written the block again. The full block variant in memory
    // stays when another face of the same block writes the + 128 variant, on
    // the other voxel frame. Any other block replaces the memory at once
    uint block_id = read_voxel_atlas(shadowcolor0, pos);
    // The texture starts out with whatever was in memory
    uint memory = uint(clamp(abs(previous.a), 0.0, 2047.0) + 0.5);
    uint memory_id = memory & 255u;
    uint age = (memory >> 8) + uint(((frameCounter >> 1) & 3) == 0);

    if (age >= voxel_memory_age) {
        memory_id = 0u;
    }

    // A negative sign marks a light source that the shadow pass writes on
    // every frame but voxel_frame_lit (see redirect_to_voxel_atlas()). Such a
    // voxel is dropped on the first of those frames it is missing from,
    // instead of lighting its surroundings until its memory runs out
    bool written_always = previous.a < 0.0 && memory_id != 0u;

#if !defined WORLD_NETHER
    int frame = voxel_frame(frameCounter);
    int frame_lit = voxel_frame_lit(pos);

    if (written_always && block_id == 0u && frame != frame_lit) {
        memory_id = 0u;
        written_always = false;
    }

    if (is_emitter(block_id & 127u) && frame != frame_lit
        && frame != voxel_frame_unlit) {
        written_always = true;
    }

    // Torches, lanterns and other light sources smaller than their block are
    // only written on the two voxel frames, by whichever of their faces that
    // frame takes. Waiting for their age to run out leaves a broken torch
    // shining for most of a second, so for them the age holds a state:
    //   1, 2, 3  seen on the unlit frame, the lit frame, both
    //   4, 5     missing from the unlit or lit frame, wait for the other one
    // A closed shape has faces on both frames at any sun angle, so one seen on
    // both is dropped the first time either misses it. A flat one moves from
    // one frame to the other as the sun passes its plane, and is given until
    // the other frame
    bool on_voxel_frame
        = frame == voxel_frame_unlit || frame == frame_lit;
    uint frame_bit = frame == voxel_frame_unlit ? 1u : 2u;
    uint written_id = block_id;
    uint source_state = 0u;
    bool small_source = memory_id >= 128u && is_emitter(memory_id & 127u)
        && !written_always;

    if (small_source) {
        source_state = min(memory >> 8, 5u);

        if (block_id == 0u && on_voxel_frame) {
            if (source_state == 3u || source_state == 6u - frame_bit) {
                memory_id = 0u;
            } else if (source_state == frame_bit) {
                source_state = 3u + frame_bit;
            }
        }

        age = source_state;
    }
#endif

    if (block_id == 0u || memory_id + 128u == block_id) {
        block_id = memory_id;
    } else {
        age = 0u;
    }

#if !defined WORLD_NETHER
    if (written_id >= 128u && is_emitter(written_id & 127u) && on_voxel_frame
        && !written_always) {
        age = (small_source && written_id == memory_id && source_state <= 3u
                ? source_state
                : 0u)
            | frame_bit;
    }
#endif

    written_always = written_always && is_emitter(block_id & 127u);

    light_out.a = block_id == 0u
        ? 0.0
        : float(block_id + 256u * age) * (written_always ? -1.0 : 1.0);

#endif

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
