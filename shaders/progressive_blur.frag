#version 460 core

#include <flutter/runtime_effect.glsl>

// One pass of a gaussian blur whose strength falls off down the screen: full
// down to u_full, easing to nothing at u_end. Run once across and once down.

uniform vec2 u_size;
uniform vec2 u_direction;
uniform float u_sigma;
uniform float u_full;
uniform float u_end;
uniform sampler2D u_input;

out vec4 frag_color;

const int TAPS = 24;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  float y = uv.y * u_size.y;
  float sigma = u_sigma * (1.0 - smoothstep(u_full, u_end, y));
  vec4 color = texture(u_input, uv);
  if (sigma < 0.5) {
    frag_color = color;
    return;
  }
  float spacing = sigma * 3.0 / float(TAPS);
  vec4 sum = color;
  float total = 1.0;
  for (int i = 1; i <= TAPS; i++) {
    float d = float(i) * spacing;
    float w = exp(-0.5 * d * d / (sigma * sigma));
    vec2 offset = u_direction * d / u_size;
    sum += (texture(u_input, clamp(uv + offset, 0.0, 1.0)) +
            texture(u_input, clamp(uv - offset, 0.0, 1.0))) * w;
    total += 2.0 * w;
  }
  frag_color = sum / total;
}
