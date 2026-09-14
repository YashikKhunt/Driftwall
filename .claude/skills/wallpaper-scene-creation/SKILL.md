---
name: wallpaper-scene-creation
description: Use when adding a new built-in generative wallpaper scene to Driftwall (a SwiftUI/Metal macOS app), or when asked to grow/organize the wallpaper catalog (e.g. the Library tab in Plan.md). Covers the Scene model, the single-shader-source Metal renderer pattern, and recipes for different visual styles (aurora/wave, ocean, gradient, particle, geometric, fractal, terrain).
---

# Wallpaper scene creation

Driftwall's built-in wallpapers are not images or videos — they are procedural
Metal fragment shaders, all compiled from one shader source string at runtime and
selected at draw time by an integer `kind`/`mode`. This skill explains how to add a
new one correctly and consistently, and gives ready-to-adapt shader recipes for
common wallpaper "types" (nature, ocean, space, abstract, minimal, seasonal).

Use this together with `Plan.md` at the repository root, which describes the wider
"Library tab" feature this catalog growth is part of.

## The pattern (read the real code first)

Two files define every scene:

- `Sources/Scenes.swift`
  - `struct Scene { id, name, subtitle, kind, colors, category }` — one entry per
    wallpaper in `Scene.all`.
  - `SceneRenderer` — compiles `SceneRenderer.shader` (one big Metal source string)
    and calls `fragmentMain(in, u)` every frame, where `u = (width, height, elapsed,
    kind)`. `elapsed` is seconds of animation time (not clock time), so scenes
    always start from `t = 0` and loop smoothly forever.
- `Tests/RenderSmoke.swift` renders every `Scene.all` entry at `t=0` and `t=12` and
  asserts the frame (a) changes over time and (b) has more than 20 distinct
  brightness values (i.e. it isn't a flat color). Any new scene must pass both
  checks — this is the main thing to verify after adding one.

## Checklist for adding one new scene

1. Pick a `category` (`Nature`, `Ocean`, `Space`, `Abstract`, `Minimal`, or add a new
   one if it earns its own bucket — don't create a category for a single scene).
2. Pick the next unused `kind` integer. **Never reuse or renumber an existing kind**
   — saved user preferences (`UserDefaults` "selected"/"active") reference scenes by
   `id`, and shader branches are looked up by `kind`; changing either breaks
   existing users' saved wallpaper.
3. Write `name` (2-3 words, plain English) and `subtitle` (one short evocative
   line, no ending punctuation, matching the tone of existing subtitles like "A
   quiet sky, alive with color").
4. Add the `Scene` entry to `Scene.all` (append at the end).
5. Add an `else if (mode == N) { ... }` branch to `fragmentMain`, using one of the
   recipes below as a starting point. Reuse the shader's existing conventions:
   - `p` = aspect-corrected, centered UV (`(uv - 0.5) * float2(u.x/u.y, 1.0)`).
   - `t` = `u.z * 0.12` — a slow, already-scaled time value. Multiply `t` by extra
     small constants (0.1-2.0) for different motion speeds; don't use `u.z` raw.
   - `c` starts near-black (`float3(0.012,0.023,0.065)`); scenes build up color by
     adding glow/gradient terms, not by fully overwriting `c` (except the two scenes
     that intentionally paint a full-frame gradient background, dunes/mode 2).
   - The `hash(float2)` helper and the twinkling star overlay
     (`if(mode==0 || mode==3) { ... }`) can be reused by adding your new mode to
     that `if` condition instead of duplicating the star loop.
   - Keep the final vignette line (`c *= 1.0-.28*length(uv-.5);`) applying to your
     scene too — it runs unconditionally after the mode dispatch.
6. Run `bash scripts/test.sh` and confirm `PASS: <Your Scene Name> renders and
   animates`. If it fails "lacks image detail", add more spatial variation
   (gradients, noise, multiple overlapping shapes); if it fails "does not animate",
   make sure some term in your branch actually depends on `t`.
7. Run `bash scripts/build.sh` to confirm the app still builds.

## Shader recipes by wallpaper type

These are starting points, not exact code to copy verbatim — adapt constants so
each scene looks distinct from its neighbors (vary loop counts, frequencies, color
palettes, and speeds).

### Aurora / ribbon flow (Nature, Abstract)

Stacked sine-wave glow bands drifting horizontally, like the existing `aurora`
(mode 0) and `silk` (mode 4) scenes.

```metal
for (int i = 0; i < 5; i++) {
    float f = float(i);
    float y = -0.08 + 0.16*sin(p.x*2.4 + t + f*0.32) + 0.065*sin(p.x*6.0 - t*0.7 + f);
    float glow = exp(-abs(p.y - y - f*0.025) * (14.0 + f*3.0));
    c += glow * mix(COLOR_A, COLOR_B, f/5.0) * 0.4;
}
```
Vary: band count, `y` amplitude/frequency, glow falloff exponent, and the two
mixed colors. Slower `t` multiplier + fewer bands reads as "minimal"; faster +
more bands + saturated colors reads as "abstract".

### Wave field (Ocean, Nature-as-grass, Seasonal)

Layered horizontal bands with a bright leading edge, like `ocean`/`forest` (modes
1 and 5).

```metal
for (int i = 0; i < 7; i++) {
    float f = float(i);
    float y = -0.4 + f*0.12 + 0.045*sin(p.x*5.0 + t + f) + 0.025*sin(p.x*11.0 - t + f);
    float wave = smoothstep(y-0.025, y+0.09, p.y) * (1.0 - smoothstep(y+0.09, y+0.2, p.y));
    c += wave * BASE_COLOR;
    c += exp(-abs(p.y - y) * 180.0) * 0.12 * HIGHLIGHT_COLOR;
}
```
Vary: layer count/spacing (tight+many = grass/meadow; wide+few = coastal waves),
`BASE_COLOR`/`HIGHLIGHT_COLOR` palette, and wave frequency for chop vs. swell.

### Gradient drift (Minimal, Ocean/lagoon, Seasonal)

A soft full-frame gradient plus one or two slow radial glows — cheap, calm, good
for "Minimal" category scenes.

```metal
c = mix(COLOR_TOP, COLOR_BOTTOM, uv.y + 0.05*sin(t*0.3));
c += exp(-length(p - float2(0.3*sin(t*0.15), 0.15*cos(t*0.12))) * 2.2) * GLOW_COLOR * 0.5;
```
Vary: how many drifting glow terms you add (0-2), how far apart `COLOR_TOP`/
`COLOR_BOTTOM` are (subtle for Minimal, bold for Seasonal), and glow speed.

### Space / nebula (Space)

Soft drifting cloud masses plus the shared star overlay, like `cosmos` (mode 3).

```metal
float cloud = exp(-abs(p.y - 0.18*sin(p.x*3.0 + t)) * 5.0);
c += cloud * (0.5 + 0.5*sin(p.x*4.0 - t)) * CLOUD_COLOR;
c += exp(-length(p - float2(0.25*sin(t*0.2), 0.1)) * 3.0) * CORE_COLOR;
// remember to add your mode to: if(mode==0 || mode==3 || mode==YOUR_MODE) for stars
```
Vary: number of overlapping `cloud`/glow terms, palette (teal/violet nebula vs.
warm/orange nebula), and whether you include the star layer at all (a plain
starfield with no nebula clouds is also a valid, cheap "Space" scene).

### Geometric / tessellation (Abstract)

Hard-edged repeating shapes using `fract`/`floor` on a scaled grid, for a more
"pattern" look than the organic ribbon/wave recipes.

```metal
float2 grid = p * 6.0 + float2(t*0.15, t*0.1);
float2 cell = fract(grid) - 0.5;
float d = max(abs(cell.x), abs(cell.y)); // square cells; use length(cell) for circles
float shape = smoothstep(0.42, 0.38, d);
float cellId = hash(floor(grid));
c += shape * mix(COLOR_A, COLOR_B, cellId) * 0.5;
```
Vary: grid scale, cell shape (`max(abs)` = squares, `length` = circles/dots,
`abs(cell.x)+abs(cell.y)` = diamonds), and drift direction/speed.

### Particle / orbit field (Abstract, Space)

A handful of moving point-glows on elliptical paths, good for "orbit" or
"firefly" style scenes.

```metal
for (int i = 0; i < 8; i++) {
    float f = float(i);
    float angle = t*0.4 + f*0.9;
    float2 pos = float2(cos(angle)*(0.25+0.05*f), sin(angle)*(0.15+0.03*f));
    c += exp(-length(p - pos) * 30.0) * mix(COLOR_A, COLOR_B, f/8.0);
}
```
Vary: particle count, orbit radii/speeds (uniform = calm "minimal orbit",
staggered = busy "particle field"), and whether particles leave a faint trail
(add a second, dimmer `exp(-length(...) * lower_exponent)` term).

### Noise terrain (Nature/canyon, Space/starfield-only)

Layered horizontal silhouettes plus a warm/cool gradient sky, like `dunes` (mode
2) — good for canyon, mountain, or horizon-style scenes.

```metal
c = mix(SKY_LOW, SKY_HIGH, uv.y);
for (int i = 0; i < 5; i++) {
    float f = float(i);
    float y = 0.06 - f*0.13 + 0.07*sin(p.x*2.5 + f*1.5 + t*0.25);
    c = mix(c, mix(RIDGE_NEAR, RIDGE_FAR, f/4.0), 1.0 - smoothstep(y-0.003, y+0.003, p.y));
}
```
Vary: ridge count/spacing (few+wide = distant mountains, many+narrow = jagged
canyon), sky palette (warm sunset vs. cool dawn vs. near-monochrome night for a
starfield-only variant with no sun disc).

## Category guidance

- **Nature** — organic, earthy: dunes, meadows, forests, canyons. Warm or
  earth-toned palettes; wave-field or noise-terrain recipes.
- **Ocean** — water and coastline: waves, lagoons, tides. Blue/cyan/teal
  palettes; wave-field or gradient-drift recipes.
- **Space** — sky and cosmos: nebulae, starfields, orbits. Deep blues/purples/
  black; nebula or particle recipes, often combined with the shared star overlay.
- **Abstract** — non-representational motion: ribbons, geometric patterns,
  particle fields. Any palette; aurora/ribbon, geometric, or particle recipes.
- **Minimal** — calm, low-contrast, slow: single or two-tone gradients with at
  most one gentle moving element. Gradient-drift recipe, low animation speed.
- **Seasonal** (optional, add only if requested) — palettes evoking a season or
  holiday (e.g. warm autumn, cool winter) built from wave-field or gradient-drift
  recipes with a matching color choice.

## Common mistakes to avoid

- Reusing an existing `kind` integer or `id` string — this silently corrupts
  another scene or breaks a returning user's saved wallpaper.
- Making a scene whose appearance doesn't change over time (fails the smoke test's
  "does not animate" check) — always tie at least one term to `t`.
- Making a scene that's nearly a flat color (fails "lacks image detail") — ensure
  spatial variation across `p`/`uv`, not just a uniform color wash.
- Forgetting the vignette / star-overlay interactions — check whether your scene
  should opt into the shared star layer (`mode==0 || mode==3 || ...`).
- Introducing a brand-new category for a single scene — prefer fitting into the
  existing category list unless several planned scenes justify a new one.
