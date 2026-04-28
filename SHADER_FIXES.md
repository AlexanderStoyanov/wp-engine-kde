# LWE Shader Compilation Fixes

This document tracks HLSL-to-GLSL shader compilation issues discovered in
[linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) (LWE)
and the patches we maintain in our
[fork](https://github.com/AlexanderStoyanov/linux-wallpaperengine).

## Background

Wallpaper Engine (Windows) uses HLSL-flavored shaders. LWE translates these to
GLSL via `glslang` + `SPIRV-Cross`. The translation layer lives in:

| File | Role |
|------|------|
| `src/WallpaperEngine/Render/Shaders/ShaderUnit.cpp` | Preprocessor: `#include`, `#require`, variable substitution, HLSL compat macros (`SHADER_HEADER`) |
| `src/WallpaperEngine/Render/Shaders/GLSLContext.cpp` | Compiler: feeds preprocessed source to `glslang`, converts SPIR-V back to GLSL via `spirv_cross` |

Wallpaper Engine's shader pipeline has features that LWE doesn't fully
implement, causing scenes to render as gray/black when shaders fail to compile.

## PR strategy

Each fix gets its **own branch and PR** — one issue per PR, minimal diff,
backward-compatible (no regressions for wallpapers that already work).

| # | Branch | PR | Status | Issue |
|---|--------|----|--------|-------|
| 1 | `fix/wayland-kde-click-through` | [#528](https://github.com/Almamu/linux-wallpaperengine/pull/528) | Submitted | Wayland: click-through + BOTTOM layer |
| 2 | `fix/require-module-resolution` | [#529](https://github.com/Almamu/linux-wallpaperengine/pull/529) | Submitted | `#require` directive resolution (LightingV1 stub) |
| 3 | `fix/hlsl-log10-macro-conflict` | [#530](https://github.com/Almamu/linux-wallpaperengine/pull/530) | Submitted | `log10` macro missing parentheses |
| 4 | `fix/hlsl-vector-type-mismatch` | [#531](https://github.com/Almamu/linux-wallpaperengine/pull/531) | Submitted | Implicit `vecN * vecM` truncation |

## Discovered issues

### 1. `#require` directives not resolved (FIXED)

**Symptom**: `PerformLighting_V1` undefined; gray scene.

**Root cause**: Wallpaper Engine dynamically generates module code when it
encounters `#require LightingV1`. LWE commented out the directive but never
injected the module, leaving functions like `PerformLighting_V1` undefined.

**Fix** (`ShaderUnit.cpp`):
- Parse the module name from `#require <ModuleName>`.
- Dispatch to `resolveRequireModule()` → `generateLightingV1()`.
- `generateLightingV1()` returns a stub that returns `vec3(0.0)` — no dynamic
  lighting, but the shader compiles and the scene renders with ambient light.
- LWE already logs `"Light objects are not supported yet"` in `ObjectParser.cpp`,
  so the stub is consistent with current engine capabilities.

**Impact**: 27 of 37 tested scene wallpapers use `#require LightingV1`. All 27
now compile successfully.

**Files changed**: `ShaderUnit.cpp`, `ShaderUnit.h` (additive only).

---

### 2. `log10` macro missing parentheses (FIXED)

**Symptom**: Incorrect rendering in shaders that divide by `log10(x)`.

**Root cause**: `SHADER_HEADER` defined `#define log10(x) log2(x) * 0.301029995663981`
without wrapping parentheses. An expression like `1.0 / log10(x)` expands to
`1.0 / log2(x) * 0.301029995663981` — division binds first due to left-to-right
evaluation, producing incorrect results.

**Fix** (`ShaderUnit.cpp`):
- Parenthesize the macro body: `(log2(x) * 0.301029995663981)`.
- Matches the convention used by other `SHADER_HEADER` macros (`mul`, `saturate`,
  `fmod`).

**Note**: An earlier version of this fix also included a `preprocessHlslCompat()`
pass to handle `log10` macro-function redefinition conflicts. That was removed
because the specific wallpapers that triggered the conflict (Sakura Reflections,
Sakura Village) were updated and no longer reproduce the issue.

**Files changed**: `ShaderUnit.cpp` (1 line).

---

### 3. Implicit vector type truncation (FIXED)

**Symptom**: `wrong operand types: no operation '*' exists that takes a left-hand
operand of type 'vec4' and a right operand of type 'vec2'`.

**Root cause**: HLSL implicitly truncates larger vectors in mixed-size
multiplications (`float4 * float2` silently uses `.xy`). GLSL requires explicit
swizzling.

**Fix** (`GLSLContext.cpp`):
- Retry loop around `glslang::TShader::parse()` (up to 8 retries).
- On failure, `fixVectorTypeMismatch()` parses the error log to extract the
  line number and component counts.
- Identifies the larger-component variable on the error line using declaration
  scanning (`uniform vec4 v_PointerUV`, etc.).
- Inserts the appropriate swizzle (`.xy`, `.xyz`, `.x`) and retries compilation.

**Impact**: Fixes Azur Lane (3326693446) — the `iris_follow_cursor.vert` effect
had `v_PointerUV` declared as `vec4` but multiplied by `vec2` scale uniforms.

**Files changed**: `GLSLContext.cpp`, `GLSLContext.h`.

---

### 4. Ephemeral: `syntax error, unexpected IDENTIFIER` (TODO)

**Wallpaper**: Ephemeral (2411455579)  
**Error**: `ERROR: 0:433: '' : syntax error, unexpected IDENTIFIER`  
**Status**: Not yet investigated. Likely another HLSL construct that doesn't
translate to GLSL. Needs dump of the preprocessed fragment shader to identify
the exact construct.

---

### 5. Non-shader engine limitations (WONTFIX — upstream LWE)

These are not shader issues and require engine-level implementation:

| Wallpaper | Error | Root cause |
|-----------|-------|------------|
| Coding Desk (2412448157) | `ReferenceError: thisScene is not defined` | LWE's JS ScriptEngine doesn't expose the `thisScene` API |
| Kurumi Tokisaki (3333919157) | `ReferenceError: engine is not defined` | LWE's JS ScriptEngine doesn't expose the `engine` API |
| Kurumi Tokisaki (3333919157) | `Text objects are not supported yet` | LWE hasn't implemented text layer rendering |
| Kurumi Tokisaki (3333919157) | `Invalid vector format: centre` | Data parsing issue with non-standard vector property names |

## E2E test results

Tested all 37 scene wallpapers in the local Steam workshop library.

| Result | Count | Wallpapers |
|--------|-------|------------|
| **OK** | 34 | See full list below |
| **SHADER_ERR** | 1 | Ephemeral |
| **ENGINE_ERR** | 2 | Coding Desk, Kurumi Tokisaki |

Note: Sakura Reflections and Sakura Village previously had `log10` errors
but were updated by their authors and now compile without patches.

### Full OK list (32 wallpapers)

| Workshop ID | Title | Fixes applied |
|-------------|-------|---------------|
| 1096335905 | Idyll's Fall [2560x1600] | — |
| 1117170220 | Gantry and Sunshine | `#require` |
| 1183845329 | Winter | `#require` |
| 1245412789 | Fantasy Forest | `#require` |
| 1326543560 | DARK SOULS 3 | `#require` |
| 1440663699 | DARK SOULS III Wallpaper 003 | `#require` |
| 1582848900 | Enchanted Forest | `#require` |
| 1687447457 | Sekiro Ice | `#require` |
| 1753302454 | Sekiro: Shadows Die Twice | — |
| 1926677846 | Mt. Fuji Japan [4k] | `#require` |
| 2012774374 | The Spring! | `#require` |
| 2025061153 | M7 - Magic Tree | `#require` |
| 2069266496 | Gravity Falls | `#require` |
| 2104291093 | Sekiro Shadows Die Twice 2 [8k] | `#require` |
| 2138655350 | Summer by Gydwin in 4K | `#require` |
| 2141227110 | Roche Limit | `#require` |
| 2237110774 | Cyberpunk 2077 Neon Night | `#require` |
| 2258024871 | Noche de Brujas | `#require` |
| 2306377941 | Sekiro: Shadow Die Twice (米娘) | `#require` |
| 2325188052 | Torii: Winter by Surendra in 4K | `#require` |
| 2451612805 | La Creación de cheems | `#require` |
| 2477602742 | Summer Feeling | `#require` |
| 2509430104 | Pine forest | `#require` |
| 3174556087 | Cozy, LoFi Shop | `#require` |
| 3236114867 | 碧蓝档案便利屋68 | `#require` |
| 3303387977 | Ghibli Coffee Shop 4K | `#require` |
| 3303562907 | As spring blossoms 4K | `#require` |
| 3326693446 | Azur Lane (BTB) | `#require` + `hlsl_fix` |
| 3559447448 | DNF NenMaster | `#require` |
| 3559487254 | Genshin Impact - Keqing 4k | `#require` |
| 3561293402 | Genshin Impact - Barbara 4k | `#require` |
| 3565747436 | Japanese temple by the lake in autumn | `#require` |

## Fix/test pipeline

### Prerequisites

- Steam with Wallpaper Engine installed (for assets and workshop content)
- LWE built from source (the fork, not upstream)
- `distrobox` recommended for immutable distros (see `build-lwe.sh` in wp-engine-kde)

### Building LWE after making changes

```bash
cd ~/Documents/Sites/linux-wallpaperengine/build
cmake --build . -j$(nproc)
```

If building inside distrobox:
```bash
distrobox enter lwe-build
cd ~/Documents/Sites/linux-wallpaperengine/build
cmake --build . -j$(nproc)
exit
```

### Testing a single wallpaper

```bash
# Quick test — runs for 5 seconds then exits (timeout)
timeout 5 ~/.local/bin/linux-wallpaperengine \
    --assets-dir ~/.local/share/Steam/steamapps/common/wallpaper_engine/assets \
    --disable-mouse --screen-root DP-2 --fps 5 \
    <WORKSHOP_ID> > /tmp/lwe-test.log 2>&1

# Check for errors
grep -E "parsing Failed|error C|Error" /tmp/lwe-test.log
```

### Testing all scene wallpapers (batch)

```bash
for wid in $(ls ~/.local/share/Steam/steamapps/workshop/content/431960/); do
  proj=~/.local/share/Steam/steamapps/workshop/content/431960/$wid/project.json
  [ -f "$proj" ] || continue
  type=$(python3 -c "import json; print(json.load(open('$proj')).get('type',''))" 2>/dev/null)
  [ "$type" = "scene" ] || continue
  title=$(python3 -c "import json; print(json.load(open('$proj')).get('title','')[:50])" 2>/dev/null)

  timeout 5 ~/.local/bin/linux-wallpaperengine \
      --assets-dir ~/.local/share/Steam/steamapps/common/wallpaper_engine/assets \
      --disable-mouse --screen-root DP-2 --fps 5 \
      $wid > /tmp/lwe-test-$wid.log 2>&1

  if grep -q "parsing Failed" /tmp/lwe-test-$wid.log; then
    echo "SHADER_ERR  $wid  $title"
  elif [ $? -eq 1 ]; then
    echo "ENGINE_ERR  $wid  $title"
  else
    echo "OK          $wid  $title"
  fi
done
```

### Debugging a shader failure

1. **Get the preprocessed shader dump**:
   The build already dumps failed shaders to `/tmp/lwe_failed_fragment.glsl`
   and `/tmp/lwe_failed_vertex.glsl`. Run the wallpaper and check these files.

2. **Identify the error line**:
   The glslang error format is `ERROR: 0:<LINE>: '<token>' : <message>`.
   Find that line in the dump file.

3. **Common patterns**:

   | Error | Likely cause | Fix location |
   |-------|-------------|--------------|
   | `no matching overloaded function found` for a `SHADER_HEADER` macro name | Macro–function name collision | Check `SHADER_HEADER` macro definitions in `ShaderUnit.cpp` |
   | `wrong operand types` with `N-component vector` | HLSL implicit truncation | `GLSLContext::fixVectorTypeMismatch()` |
   | `undeclared identifier` for a function from `#require` | Missing module resolution | `ShaderUnit::resolveRequireModule()` |
   | `syntax error, unexpected IDENTIFIER` | Unknown HLSL construct | Needs investigation — dump and inspect |

4. **Iterate**:
   - Edit the relevant `.cpp` file
   - Rebuild: `cd build && cmake --build . -j$(nproc)`
   - Retest: `timeout 5 ~/.local/bin/linux-wallpaperengine --assets-dir ... --screen-root DP-2 --fps 5 <WID> > /tmp/test.log 2>&1`
   - Check: `grep "parsing Failed" /tmp/test.log`

### Code architecture notes

- `SHADER_HEADER` (defined in `ShaderUnit.cpp`) is prepended to every shader.
  It defines HLSL compatibility macros like `saturate`, `lerp`, `frac`, `log10`,
  `atan2`, `fmod`, `ddx`, `ddy`, etc. Macro bodies should be parenthesized to
  prevent operator precedence bugs when used in compound expressions.

- `m_includes` accumulates included file content during `preprocessIncludes()`
  and is inserted into `m_preprocessed` before `main()`. It is fully consumed
  by the time `preprocessRequires()` runs, so generated module code must be
  inserted directly into `m_preprocessed`.

- The preprocessing order in `ShaderUnit::preprocess()` is:
  1. `preprocessVariables()` — substitute `$VARIABLE` tokens
  2. `preprocessIncludes()` — resolve `#include` directives, insert into `m_preprocessed`
  3. `preprocessRequires()` — resolve `#require` directives, insert generated code into `m_preprocessed`

- `GLSLContext::toGlsl()` compiles vertex + fragment shaders. The retry loop
  for `fixVectorTypeMismatch` runs after all preprocessing, catching type
  errors that only appear at compile time.

### Branch management

All fix branches are based on `origin/main`. To update:

```bash
git fetch origin
git rebase origin/main fix/require-module-resolution
git rebase origin/main fix/hlsl-log10-macro-conflict
git rebase origin/main fix/hlsl-vector-type-mismatch
```

The fork's `main` branch tracks `origin/main`. Individual fix branches contain
exactly one commit each for clean PRs.
