#version 460 core

#include <flutter/runtime_effect.glsl>

// Cheap animated PS3 XMB-inspired silk wave ribbons (no texture fetches, no blur).
// Uniform order must match ShaderBackground: uSize, uTime, uColorA, uColorB.
uniform vec2 uSize;
uniform float uTime;
uniform vec4 uColorA;
uniform vec4 uColorB;

out vec4 fragColor;

float ribbonGlow(vec2 uv, float freq, float speed, float amp, float yCenter, float width) {
  float w = sin(uv.x * freq + uTime * speed) * amp
          + cos(uv.x * (freq * 1.73) - uTime * (speed * 0.65)) * (amp * 0.45);
  float dist = abs(uv.y - yCenter - w);
  float core = smoothstep(width, 0.0, dist);
  float halo = smoothstep(width * 6.0, 0.0, dist) * 0.25;
  return core + halo;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  vec4 base = mix(uColorA, uColorB, clamp(uv.y * 0.92 + uv.x * 0.12, 0.0, 1.0));

  float r1 = ribbonGlow(uv, 4.4, 0.32, 0.085, 0.56, 0.022);
  float r2 = ribbonGlow(uv, 6.2, -0.24, 0.065, 0.48, 0.018);
  float r3 = ribbonGlow(uv, 3.1, 0.18, 0.055, 0.63, 0.015);

  float shimmer = clamp(r1 * 0.34 + r2 * 0.24 + r3 * 0.18, 0.0, 0.65);
  vec3 tint = mix(uColorB.rgb, vec3(0.85, 0.94, 1.0), 0.55);
  fragColor = vec4(base.rgb + tint * shimmer, 1.0);
}
