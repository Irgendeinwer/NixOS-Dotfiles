// Generate Feishin's Butterchurn module from the canonical MilkDrop preset.
// Run with milkdrop-preset-converter@0.1.2 and milkdrop-preset-utils@0.1.0
// available in NODE_PATH.
const fs = require('node:fs');
const path = require('node:path');
const converter = require('milkdrop-preset-converter');
const presetUtils = require('milkdrop-preset-utils');

const sourcePath = path.join(
  __dirname,
  './royal-mashup-remix.milk',
);
const outputPath = path.join(
  __dirname,
  './royal-mashup-remix.butterchurn.ts',
);

// The old HLSL-to-GLSL converter does not reliably translate this preset's
// pixel shaders. Keep their Butterchurn GLSL equivalents explicit and testable.
const warp = `shader_body {
  vec2 texel = texsize.zw;
  // Preserve the original one-sided taps; symmetric averaging blurs the history.
  vec3 shifted_x = texture(sampler_main, uv + vec2(texel.x, 0.0)).xyz;
  vec3 shifted_y = texture(sampler_main, uv + vec2(0.0, texel.y)).xyz;
  ret = shifted_x + shifted_y
      - texture(sampler_main, (uv - vec2(0.5)) * 0.9 + vec2(0.5)).xyz;
  // Original per-frame feedback: dark dissolve at rest, longer trails on impacts.
  ret -= (0.55 - 0.27 * q5);
}`;

const comp = `vec3 smooth_bloom(vec2 p) {
  // Blur3 is 1/16-resolution in both Butterchurn and projectM. Four taps at
  // half a bloom texel soften bilinear steps without adding bloom energy.
  vec2 d = texsize.zw * 8.0;
  vec3 encoded = texture(sampler_blur3, p + vec2(-d.x, -d.y)).xyz
               + texture(sampler_blur3, p + vec2( d.x, -d.y)).xyz
               + texture(sampler_blur3, p + vec2(-d.x,  d.y)).xyz
               + texture(sampler_blur3, p + vec2( d.x,  d.y)).xyz;
  return encoded * (0.25 * scale3) + vec3(bias3);
}
shader_body {
  vec2 uv_echo = vec2(1.0) - uv;
  vec2 ca_offset = (uv - vec2(0.5)) * (0.03 * q4);
  // Low ambient floor; the macro level supplies groove and impact headroom.
  float echo_gain = 0.10 + 0.75 * q6;
  float bloom_gain = 0.15 + 2.15 * q6;
  // Keep the fresh core unshifted; chromatic separation belongs to the echo.
  vec3 core = texture(sampler_main, uv).xyz;
  vec3 echo = vec3(
    texture(sampler_main, uv_echo - ca_offset).r,
    texture(sampler_main, uv_echo).g,
    texture(sampler_main, uv_echo + ca_offset).b
  );
  ret = core + echo * echo_gain;
  ret += (smooth_bloom(uv) + smooth_bloom(uv_echo)) * bloom_gain;

  // Normalize only over-range highlights, preserving hue and in-range levels.
  float peak = max(ret.r, max(ret.g, ret.b));
  ret /= max(peak, 1.0);

  // Whiten only bright high-frequency core detail, never broad fills or bloom.
  float core_peak = max(core.r, max(core.g, core.b));
  vec3 local_blur = texture(sampler_blur1, uv).xyz * scale1 + vec3(bias1);
  float blur_peak = max(local_blur.r, max(local_blur.g, local_blur.b));
  float core_detail = max(core_peak - blur_peak, 0.0);
  float core_mask = smoothstep(0.55, 0.90, core_peak)
                  * smoothstep(0.10, 0.35, core_detail);
  core_mask = core_mask * core_mask * q18;
  ret = mix(ret, vec3(1.0), core_mask);

  // Static sub-LSB dither reduces 8-bit banding without temporal shimmer.
  float dither = fract(sin(dot(uv * texsize.xy, vec2(12.9898, 78.233))) * 43758.5453);
  ret += (dither - 0.5) / 255.0;
}`;

(async () => {
  const source = fs.readFileSync(sourcePath, 'utf8');
  const preset = await converter.convertPreset(source);

  // Feishin's CSP allows WASM but blocks the new Function path used by
  // JavaScript-only presets. Include raw EEL so Butterchurn 3 uses WASM, while
  // retaining the converted JavaScript equations for older runtimes.
  const raw = presetUtils.splitPreset(source);
  preset.version = raw.presetVersion;
  preset.init_eqs_eel = raw.presetInit.trim();
  preset.frame_eqs_eel = raw.perFrame.trim();
  preset.pixel_eqs_eel = raw.perVertex.trim();
  for (let i = 0; i < preset.shapes.length; i++) {
    if (preset.shapes[i].baseVals.enabled !== 0) {
      preset.shapes[i].init_eqs_eel = raw.shapes[i].init_eqs_str.trim();
      preset.shapes[i].frame_eqs_eel = raw.shapes[i].frame_eqs_str.trim();
    }
  }
  for (let i = 0; i < preset.waves.length; i++) {
    if (preset.waves[i].baseVals.enabled !== 0) {
      preset.waves[i].init_eqs_eel = raw.waves[i].init_eqs_str.trim();
      preset.waves[i].frame_eqs_eel = raw.waves[i].frame_eqs_str.trim();
      preset.waves[i].point_eqs_eel = raw.waves[i].point_eqs_str.trim();
    }
  }

  preset.warp = warp;
  preset.comp = comp;
  const generated = [
    '// Generated from the .milk source with milkdrop-preset-converter.',
    '// Regenerate with generate-royal-butterchurn.cjs; do not hand-edit.',
    `const preset: Record<string, any> = ${JSON.stringify(preset, null, 2)};`,
    '',
    'export default preset;',
    '',
  ].join('\n');
  fs.writeFileSync(outputPath, generated);
  console.log(`Wrote ${outputPath}`);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
