#define WORLD_END
#ifdef MC_OS_MAC
void voxy_emitFragment(VoxyFragmentParameters parameters) {
    discard;
}
#else
#include "/program/voxy_opaque.glsl"
#endif
