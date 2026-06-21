#define WORLD_OVERWORLD
#ifdef MC_OS_MAC
void voxy_emitFragment(VoxyFragmentParameters parameters) {
    discard;
}
#else
#include "/program/voxy_translucent.glsl"
#endif
