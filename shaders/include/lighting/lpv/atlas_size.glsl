#if !defined INCLUDE_LIGHTING_LPV_ATLAS_SIZE
#define INCLUDE_LIGHTING_LPV_ATLAS_SIZE

// Edge length N of the voxel volume on the atlas path (see atlas.glsl).
//
// The voxel atlas is a strip 8 * N wide and N * N / 8 tall on the right of the
// shadow map, and the shadow projection gets the square left of it. A small
// shadow map therefore caps N, whatever VOXEL_VOLUME_SIZE asks for:
//
//   shadowMapResolution   N     voxel strip    shadow region
//   2048 and above        128   1024 x 2048    resolution - 1024
//   1536                  96    768 x 1152     768
//   1024                  64    512 x 512      512

#if VOXEL_VOLUME_SIZE > 128
#define LPV_ATLAS_REQUESTED_N 128
#else
#define LPV_ATLAS_REQUESTED_N VOXEL_VOLUME_SIZE
#endif

const int lpv_atlas_max_n
    = shadowMapResolution >= 2048 ? 128 : (shadowMapResolution >= 1536 ? 96 : 64);
const int lpv_atlas_n = LPV_ATLAS_REQUESTED_N < lpv_atlas_max_n
    ? LPV_ATLAS_REQUESTED_N
    : lpv_atlas_max_n;

#endif // INCLUDE_LIGHTING_LPV_ATLAS_SIZE
