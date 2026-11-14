#version 460 core

#include <flutter/runtime_effect.glsl>

// Cheap animated PS3 XMB-inspired silk wave ribbons (no texture fetches, no blur).
// Uniform order must match ShaderBackground: uSize, uTime, uColorA, uColorB.
uniform vec2 uSize;
uniform float uTime;
uniform vec4 uColorA;
uniform vec4 uColorB;

out vec4 fragColor;

float ribbonGlow(vec2 uv, float freq, float speed, float amp, float yStart, float yEnd, float width) {
  float slopeY = mix(yStart, yEnd, uv.x);
  float w = sin(uv.x * freq + uTime * speed) * amp
          + cos(uv.x * (freq * 1.55) - uTime * (speed * 0.6)) * (amp * 0.42);
  float dist = abs(uv.y - (slopeY + w));
  float core = smoothstep(width, 0.0, dist);
  float halo = smoothstep(width * 8.0, 0.0, dist) * 0.28;
  return core + halo;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  // Teal top-left sweeping down into deep navy at bottom-right (PS3 XMB palette).
  float gradMix = clamp(uv.y * 0.85 + uv.x * 0.20, 0.0, 1.0);
  vec4 base = mix(uColorA, uColorB, gradMix);

  float r1 = ribbonGlow(uv, 3.2, 0.26, 0.055, 0.34, 0.63, 0.020);
  float r2 = ribbonGlow(uv, 4.7, -0.18, 0.042, 0.40, 0.57, 0.015);
  float r3 = ribbonGlow(uv, 2.3, 0.14, 0.035, 0.46, 0.70, 0.028);

  float shimmer = clamp(r1 * 0.30 + r2 * 0.22 + r3 * 0.16, 0.0, 0.55);
  vec3 tint = mix(uColorA.rgb, vec3(0.90, 0.96, 1.0), 0.65);
  fragColor = vec4(base.rgb + tint * shimmer, 1.0);
}
