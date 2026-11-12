// Experiment (throwaway), M0 ticket 05b: refraction for BackdropFilter via
// ui.ImageFilter.shader (Impeller only). Approximates the design's `.lg`
// refract layer: a convex edge that bends more toward the rim, flat centre,
// R/G/B displaced 1.06/1.00/0.94x for dispersion.
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;     // set by the engine: size of the filter input
uniform vec4 u_rect;     // glass rect in filter-input pixels: left, top, w, h
uniform float u_radius;  // corner radius, pixels
uniform float u_edge;    // edge (bend) width, pixels
uniform float u_disp;    // max displacement, pixels
uniform float u_debug;   // 1 = paint the SDF instead of refracting

uniform sampler2D u_tex; // set by the engine: the backdrop

out vec4 frag_color;

float sdRoundBox(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + vec2(r);
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float sdf(vec2 frag) {
  vec2 c = u_rect.xy + u_rect.zw * 0.5;
  return sdRoundBox(frag - c, u_rect.zw * 0.5, u_radius);
}

vec4 sampleAt(vec2 px) {
  // No y flip on IMPELLER_TARGET_OPENGLES: the ImageFilter.shader dartdoc
  // still asks for one, but Flutter 3.47 removed the GLES texture-coordinate
  // flip and flipping samples the wrong rows (M0 ticket 05b, Android emulator).
  return texture(u_tex, px / u_size);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float d = sdf(frag);
  if (u_debug > 0.5) {
    frag_color = d < 0.0 ? vec4(clamp(-d / u_edge, 0.0, 1.0), 0.0, 0.0, 1.0)
                         : sampleAt(frag);
    return;
  }
  if (d >= 0.0) {
    frag_color = sampleAt(frag);
    return;
  }
  // 0 at the rim, 1 once we are u_edge pixels inside.
  float t = clamp(-d / u_edge, 0.0, 1.0);
  float bend = (1.0 - t) * (1.0 - t);
  // Outward normal from the SDF gradient.
  float e = 1.0;
  vec2 n = vec2(sdf(frag + vec2(e, 0.0)) - sdf(frag - vec2(e, 0.0)),
                sdf(frag + vec2(0.0, e)) - sdf(frag - vec2(0.0, e)));
  float len = length(n);
  n = len > 0.0001 ? n / len : vec2(0.0);
  // Pull samples from further inside: content near the rim is magnified and
  // bent, like the edge of a convex lens.
  vec2 off = -n * bend * u_disp;
  float r = sampleAt(frag + off * 1.06).r;
  vec4 g = sampleAt(frag + off);
  float b = sampleAt(frag + off * 0.94).b;
  frag_color = vec4(r, g.g, b, g.a);
}
