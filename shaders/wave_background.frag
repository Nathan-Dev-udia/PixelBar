#version 460 core

#include <flutter/runtime_effect.glsl>

// Cheap animated gradient "wave" background (no texture fetches, no blur).
// Uniform order must match ShaderBackground: uSize, uTime, uColorA, uColorB.
uniform vec2 uSize;
uniform float uTime;
uniform vec4 uColorA;
uniform vec4 uColorB;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float wave = sin(uv.x * 6.2831 + uTime * 0.35) * 0.08
             + sin(uv.x * 11.0 - uTime * 0.22) * 0.04;
  float band = smoothstep(0.0, 0.12, 0.012 / abs(uv.y - 0.55 - wave));
  vec4 base = mix(uColorA, uColorB, uv.y);
  fragColor = base + vec4(vec3(band * 0.35), 0.0);
}
