/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/lpv/floodfill.vsh:
  Fullscreen pass over the light atlas

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

void main() {
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
