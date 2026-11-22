#if !defined INCLUDE_LIGHTING_LPV_ATLAS
#define INCLUDE_LIGHTING_LPV_ATLAS

// Colored lights without compute shaders or image writes (OpenGL 4.1).
//
// The voxel volume is stored as 2D atlases: one N x N tile per Y slice, with X
// and Z inside the tile.
//
//   Voxel atlas: block IDs, in the red channel of shadowcolor0. It occupies a
//     strip 8 tiles wide on the right of the shadow map. The shadow projection
//     is squeezed into the square to its left (see shadow_region_res in
//     shadows/distortion.glsl). A second shadow color buffer would cost two
//     more full size clears per frame: Iris clears both textures of each one
//   Light atlas: propagated light, in colortex17, 16 tiles wide, above the
//     rows reserved for the cloud shadow map copy. Alpha remembers each
//     voxel's block ID, since the voxel atlas is only partly filled per frame
//     (see redirect_to_voxel_atlas() in voxelization.glsl)
//
// With N = 128 the voxel strip is 1024 x 2048 and the light tiles 2048 x 1024.
// N comes from atlas_size.glsl, which shrinks it when the shadow map is too
// small for the strip.

#include "voxelization.glsl"

#define light_atlas_sampler colortex17
#define voxel_atlas_sampler shadowcolor0

const int voxel_atlas_tiles_x = 8;
const int light_atlas_tiles_x = 16;

// The shadow pass voxelizes on two frames out of this many
const int voxel_frame_period = 8;
const int voxel_frame_unlit = 3; // quads facing away from the light

// Position of a frame in that cycle. Iris can advance frameCounter by two per
// frame, so the cycle runs on half the counter: no frame is skipped that way,
// at worst each one comes twice
int voxel_frame(int frame_counter) {
    return (frame_counter >> 1) % voxel_frame_period;
}

// The step on which a block gives up its quads that face the light. Those are
// the faces the shadow map shows, so taking every block's on one frame moved
// all soft shadows at once, several times a second. Each block gets its own
// step instead, from its world position, and never voxel_frame_unlit: with
// both halves gone the block would cast nothing
int voxel_frame_lit(ivec3 voxel_pos) {
    ivec3 block = voxel_pos - voxel_volume_size / 2
        - ivec3(get_voxel_volume_center(gbufferModelViewInverse[2].xyz))
        + ivec3(floor(cameraPosition));
    int phase = (block.x * 3 + block.y * 5 + block.z * 7) % 7;
    phase += phase < 0 ? 7 : 0;

    return (voxel_frame_unlit + 1 + phase) % voxel_frame_period;
}

const ivec2 voxel_atlas_origin
    = ivec2(shadowMapResolution - voxel_atlas_tiles_x * lpv_atlas_n, 0);
// The bottom rows of the light atlas texture hold a copy of the cloud shadow
// map (512 x 512 at the origin, edges repeated into the padding around it), so
// that programs short on texture units can read both through one sampler
const int light_atlas_cloud_rows = 640;
const ivec2 light_atlas_origin = ivec2(0, light_atlas_cloud_rows);
// Size of the tiled part. The texture is sized from VOXEL_VOLUME_SIZE in
// shaders.properties and is larger than this when a small shadow map caps N
const ivec2 light_atlas_tiles_size = ivec2(
    light_atlas_tiles_x * lpv_atlas_n,
    (lpv_atlas_n / light_atlas_tiles_x) * lpv_atlas_n
);

// Second set of tiles, above the light: xyz is the offset in blocks from the
// voxel to the light source that lights it most, alpha is 1 where one is known
// (see update_light_source() in program/lpv/floodfill.fsh)
const ivec2 light_atlas_source_origin
    = light_atlas_origin + ivec2(0, light_atlas_tiles_size.y);

ivec2 voxel_to_atlas(ivec3 voxel_pos, int tiles_x) {
    return voxel_pos.xz
        + lpv_atlas_n * ivec2(voxel_pos.y % tiles_x, voxel_pos.y / tiles_x);
}

ivec3 atlas_to_voxel(ivec2 texel, int tiles_x) {
    ivec2 tile = texel / lpv_atlas_n;
    ivec2 in_tile = texel - tile * lpv_atlas_n;
    return ivec3(in_tile.x, tile.x + tile.y * tiles_x, in_tile.y);
}

#if defined SHADOW_VOXEL_REDIRECT && defined vsh
// No image writes and no geometry stage on the atlas path: a quad is either
// drawn as a shadow caster or moved, whole, onto its block's texel in the
// voxel atlas. Which one depends on the frame (voxel_frame_period):
//
//   most frames  every quad casts, nothing is voxelized
//   one frame    quads facing away from the light are voxelized
//   one frame    quads facing the light are voxelized
//
// Light sources that fill their block are the exception: their quads facing
// away from the light are voxelized on every frame but the last of these.
//
// Solid geometry is closed, so either half of its faces casts the same shadow,
// and the two voxel frames together reach every block that has a face at all.
// program/lpv/floodfill.fsh remembers each voxel between its frames. Without a
// light (Nether) every quad is voxelized on every frame.
//
// The far faces are the only casters for places whose near faces lie outside
// the loaded terrain (a cave at sunset). program/d4_deferred_shading.fsh
// covers for them with the sky lightmap.
//
// Returns true if the vertex was moved. Everything decided here has to come
// out the same for all four vertices of a quad
bool redirect_to_voxel_atlas(uint block_id) {
    voxel_id = 0;
    voxel_full = 0.0;

    vec3 voxel_pos = get_block_voxel_pos();
    bool is_light_emitting_block = 32u <= block_id && block_id < 80u;

    // Leaves always cast and are never voxelized: the holes in their near and
    // far faces differ, so a shadow from half of the faces would flicker
    bool is_leaves = block_id == 5u;

    if (!is_voxelized(block_id, true) || is_leaves
        || !is_inside_voxel_volume(voxel_pos)) {
        return false;
    }

    // Quads inside the block (plants, panes, carpets, ladders) are not part of
    // a closed shape, so nothing else casts their shadow on the frame they are
    // taken away, and the shadow flickers. They cannot mark a full block
    // either, so only light sources give theirs up. The distance from the
    // block centre along the normal is the same for the whole quad
    bool on_block_face = abs(dot(at_midBlock.xyz, gl_Normal)) > 31.0;

    if (!on_block_face && !is_light_emitting_block) {
        return false;
    }

#if !defined WORLD_NETHER
    // The shadow view looks along -Z, so its Z axis points at the light
    bool faces_light = dot(gl_Normal, shadowModelViewInverse[2].xyz) > 0.0;

#if defined PROGRAM_SHADOW_WATER
    // Translucent blocks keep the faces nearest the light as casters, which
    // carry the tint of the shadow, and voxelize the others on every frame
    if (faces_light) {
        return false;
    }
#else
    int frame = voxel_frame(frameCounter);

    // Light sources also voxelize their far faces on the frames in between,
    // so that placing, breaking or switching one shows at once. Only faces on
    // the outside of the block: those belong to closed shapes, whose near
    // faces cast the same shadow, while a torch needs all of its planes. The
    // distance from the block centre along the normal is the same for the
    // whole quad. On voxel_frame_lit the far faces cast instead
    int frame_lit = voxel_frame_lit(ivec3(voxel_pos));
    bool always_voxelized = is_light_emitting_block && on_block_face
        && !faces_light && frame != frame_lit;

    if (!always_voxelized
        && frame != (faces_light ? frame_lit : voxel_frame_unlit)) {
        return false;
    }
#endif
#endif

    bool vertex_at_grid_corner = is_vertex_at_grid_corner();

    // The fragment shader sorts out what the block is: a quad with a vertex on
    // the block grid is a full block (voxel_full is interpolated, so three of
    // the four vertices have a say), any other is a transparent light source
    // or nothing. Bit 8 marks light sources
    voxel_id = int(min(get_voxel_id(block_id), 127u))
        + (is_light_emitting_block ? 256 : 0);
    voxel_full = float(vertex_at_grid_corner);

    // Which corner of the quad this is, from the side of the sprite's centre
    // its texture coordinate is on. gl_VertexID would be simpler, but it does
    // not count from a multiple of four in every chunk section.
    //
    // The quad becomes a 1.2 texel square around the texel centre. The centre
    // sits off both diagonals, so it falls well inside one triangle whichever
    // way the quad is split, and no other texel centre is covered
    vec2 corner = step(mc_midTexCoord, gl_MultiTexCoord0.xy);

    vec2 texel = vec2(
        voxel_atlas_origin
        + voxel_to_atlas(ivec3(voxel_pos), voxel_atlas_tiles_x)
    );
    vec2 ndc = (texel + 0.5 + (corner - vec2(0.5, 0.2)) * 1.2)
        * (2.0 / float(shadowMapResolution))
        - 1.0;

    // Full blocks get the nearer depth, so they win the depth test over a
    // transparent light source written to the same voxel. Both sit at the
    // near plane, in front of any shadow caster that reaches into the strip
    gl_Position = vec4(ndc, vertex_at_grid_corner ? -0.999 : -0.998, 1.0);

    return true;
}
#endif

#if !defined PROGRAM_SHADOW
// Block ID written by the shadow pass this frame
uint read_voxel_atlas(sampler2D voxel_atlas, ivec3 voxel_pos) {
    ivec2 texel
        = voxel_atlas_origin + voxel_to_atlas(voxel_pos, voxel_atlas_tiles_x);
    return uint(texelFetch(voxel_atlas, texel, 0).x * 255.0 + 0.5);
}

vec3 read_light_atlas(sampler2D light_atlas, ivec3 voxel_pos) {
    return texelFetch(
               light_atlas,
               light_atlas_origin
                   + voxel_to_atlas(voxel_pos, light_atlas_tiles_x),
               0
    )
        .rgb;
}

// Trilinear lookup. `pos` is the position in the volume on [0, 1]. Bilinear
// filtering covers X and Z, the two nearest Y slices are blended by hand. The
// XZ coordinate is kept half a texel inside the tile so that the filter never
// reaches a neighbouring slice
vec3 sample_light_atlas(sampler2D light_atlas, vec3 pos) {
    float n = float(lpv_atlas_n);
    vec3 voxel_pos = pos * n;

    vec2 xz = clamp(voxel_pos.xz, 0.5, n - 0.5);
    float y = clamp(voxel_pos.y - 0.5, 0.0, n - 1.0);
    float y0 = floor(y);
    float y1 = min(y0 + 1.0, n - 1.0);

    const float tiles_x = float(light_atlas_tiles_x);
    vec2 texel_size = 1.0 / vec2(textureSize(light_atlas, 0));

    vec2 tile0 = vec2(mod(y0, tiles_x), floor(y0 / tiles_x));
    vec2 tile1 = vec2(mod(y1, tiles_x), floor(y1 / tiles_x));

    vec2 origin = vec2(light_atlas_origin) + xz;

    vec3 light0
        = textureLod(light_atlas, (origin + n * tile0) * texel_size, 0.0).rgb;
    vec3 light1
        = textureLod(light_atlas, (origin + n * tile1) * texel_size, 0.0).rgb;

    return mix(light0, light1, y - y0);
}
#endif

#endif // INCLUDE_LIGHTING_LPV_ATLAS
