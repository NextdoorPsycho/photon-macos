/*
--------------------------------------------------------------------------------

  Photon Shader by SixthSurge

  program/d3_ao:
  Calculate ambient occlusion

--------------------------------------------------------------------------------
*/

#include "/include/global.glsl"

out vec2 uv;

void main() {
    uv = gl_MultiTexCoord0.xy;
    // The ambient buffers are half the size of the view. With render scaling
    // only their lower left corner is used, like the full-size buffers
    gl_Position
        = vec4(gl_Vertex.xy * taau_render_scale * 2.0 - 1.0, 0.0, 1.0);
}
