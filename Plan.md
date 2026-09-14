# Plan: Add a "Library" tab and expand wallpaper variety

This document is a self-contained implementation plan for a coding agent (e.g. Claude
Code) to execute. It describes exactly what to build, in what order, and how to verify
it, so the work can be picked up and finished without re-deriving context from scratch.

Read `.claude/skills/wallpaper-scene-creation/SKILL.md` before starting section 2 — it
explains the recipe for adding new generative wallpaper *types* (aurora-style, wave,
gradient, particle, geometric, fractal, terrain, etc.) in a way that is consistent with
this codebase's Metal shader architecture.

## 1. Problem

Driftwall currently ships with a fixed set of **six** built-in generative scenes
(`Sources/Scenes.swift`, `Scene.all`) plus whatever videos the user imports. The
library window (`Sources/DriftwallApp.swift`, `LibraryView`) only has two sidebar
sections: **Discover** (the six built-in scenes) and **My videos** (imported videos).
There is no way to browse a larger, organized catalog of built-in wallpaper styles, and
no structured place to keep adding new ones over time.

## 2. Goal

Add a third sidebar tab, **Library**, that acts as the home for an expanded and
growing catalog of built-in generative wallpapers, organized into categories (e.g.
Nature, Ocean, Space, Abstract, Minimal). Grow the catalog from 6 scenes to a larger
curated set (aim for at least 16-20 total) using the scene "recipes" in the skill
file, and let the user filter the Library tab by category as well as by the existing
search box.

`Discover` remains a small, rotating "featured" surface (it can simply show a subset
or all scenes); `Library` is the full, organized catalog; `My videos` is unchanged.

## 3. Current architecture (read these first)

- `Sources/Scenes.swift`
  - `Scene` is a plain struct: `id`, `name`, `subtitle`, `kind` (an `Int` selecting a
    branch in the Metal shader), `colors` (used for card accents).
  - `Scene.all` is the hardcoded array of six scenes.
  - `SceneRenderer` compiles one big inline Metal shader source string
    (`SceneRenderer.shader`) at runtime and dispatches on `mode` (== `kind`) inside
    `fragmentMain` with `if/else if` branches.
- `Sources/WallpaperStore.swift`
  - `WallpaperStore.name(for:)` looks up a scene or video name by id. No changes
    should be required here for this feature, but double-check after adding
    category metadata.
- `Sources/DriftwallApp.swift`
  - `LibraryView` holds `@ViewState private var section = "Discover"` and a
    `sidebar` view with `nav("Discover", ...)` and `nav("My videos", ...)` buttons.
  - The grid in `body` currently does:
    `if section == "Discover" { ForEach(Scene.all...) { sceneCard($0) } }`
    followed unconditionally by the videos `ForEach`. Filtering by category and a
    third section needs to fit into this same pattern.
  - `sceneCard(_:)` and `videoCard(_:)` render individual grid cells.
- `Tests/RenderSmoke.swift` renders every `Scene.all` entry at two time points on the
  GPU and asserts the frame changes and has enough distinct pixel values. Any new
  scene `kind` must pass this.

## 4. Step-by-step plan

### 4.1 Data model: add categories

In `Sources/Scenes.swift`:

1. Add a `category: String` field to `Scene` (e.g. `"Nature"`, `"Ocean"`, `"Space"`,
   `"Abstract"`, `"Minimal"`, `"Seasonal"`). Keep category names short and stable —
   they are used as tab/filter labels.
2. Tag the existing six scenes with a sensible category (suggested):
   - `aurora` → Nature
   - `ocean` → Ocean
   - `dunes` → Nature
   - `cosmos` → Space
   - `silk` → Abstract
   - `forest` → Nature
3. Add `static let categories: [String]` computed from `all` (unique categories, in a
   stable, curated order — do not just `Set(...)` and rely on hash order).

### 4.2 New scene kinds (grow the catalog)

Using `.claude/skills/wallpaper-scene-creation/SKILL.md` as the recipe book, add new
`Scene` entries and matching shader branches. Suggested first batch (10 new scenes,
bringing the total to 16):

| id | name | category | shader recipe (see skill) |
|---|---|---|---|
| `nebula` | Nebula Drift | Space | fractal-bloom |
| `starfield` | Deep Starfield | Space | noise-terrain (star layer only, no ground) |
| `waves` | Coastal Waves | Ocean | wave-field (higher frequency, foam highlights) |
| `lagoon` | Glass Lagoon | Ocean | gradient-drift + wave-field mix |
| `meadow` | Golden Meadow | Nature | wave-field tuned to look like grass |
| `canyon` | Red Canyon | Nature | noise-terrain, warm palette |
| `prism` | Prism Field | Abstract | geometric-tessellation |
| `orbits` | Orbit Lines | Abstract | particle-field (ring orbits) |
| `mono` | Quiet Mono | Minimal | gradient-drift, single hue, slow |
| `blush` | Soft Blush | Minimal | gradient-drift, pastel palette |

For each new scene:

1. Add an entry to `Scene.all` with a unique `kind` integer (next unused integer;
   currently 0-5 are taken, so start at 6).
2. Add an `else if (mode == N) { ... }` branch to `fragmentMain` in
   `SceneRenderer.shader` implementing the recipe. Keep the same coordinate
   conventions already used (`p` is aspect-corrected, centered UV; `t` is slow time).
3. Reuse helper patterns already in the shader (the star-field overlay under
   `if(mode==0 || mode==3)`, the `hash` function, ribbon/wave loops) instead of
   duplicating logic where a new scene is a close variant.
4. Keep the shader a single source string (current architecture choice) unless the
   `switch`/`if-else` chain becomes hard to read — if so, splitting into per-mode
   Metal functions called from `fragmentMain` is an acceptable refactor, but keep the
   change minimal and behavior-preserving for existing kinds 0-5.

### 4.3 UI: third sidebar tab + category filter

In `Sources/DriftwallApp.swift`:

1. Add `nav("Library", icon: "square.stack.3d.up")` to `sidebar` (between
   `"Discover"` and `"My videos"`, or after `"Discover"` — Discover, Library, My
   videos reads best).
2. Add `@ViewState private var category = "All"` to `LibraryView`.
3. When `section == "Library"`, render a horizontal row of category filter chips
   above the grid (`"All"` plus `Scene.categories`), each toggling `category`.
   Reuse the existing pill/button visual language (see `nav`/card styles) rather
   than introducing a new component style.
4. Update the grid population logic:
   - `Discover`: unchanged, or reduce to a small featured subset (e.g. first 6 scenes
     by id, or a hand-picked `Scene.featured` list) — pick whichever keeps the
     "Discover" copy ("Original scenes for your everyday escape") coherent once the
     catalog has grown behind Library. Simplest correct option: keep Discover
     showing everything it shows today, unfiltered.
   - `Library`: show `Scene.all` filtered by `category` (unless `"All"`) and by the
     existing `search` text field, same `localizedCaseInsensitiveContains` pattern
     used today.
   - `My videos`: unchanged (videos only).
5. Update the header copy (`Text(section == "Discover" ? ... : ...)`) to add a third
   case for `Library`, e.g. title "Every atmosphere." / subtitle "Browse the full
   collection by mood."
6. Update the `"THE COLLECTION" / "YOUR LIBRARY"` label logic similarly to show
   something like `"LIBRARY  ·  \(category.uppercased())"` when in the Library
   section.
7. `sceneCard(_:)` can optionally show `scene.category` in place of / alongside the
   existing "LIVE SCENE · METAL" caption when in the Library tab; keep it simple if
   time-boxed (leaving the caption as-is is fine).

### 4.4 Tests and docs

1. `Tests/RenderSmoke.swift` already iterates `Scene.all`, so every new scene is
   covered automatically — run `bash scripts/test.sh` and confirm all new scenes
   print `PASS` and none fail the "does not animate" / "lacks image detail" checks.
   If a new recipe is too static or low-contrast, tune constants until it passes.
2. Update `README.md`:
   - "Six original animated scenes: ..." → update the count and either list all
     scenes or say "N original animated scenes across Nature, Ocean, Space,
     Abstract, and Minimal collections."
   - Mention the new Library tab under Features, e.g. "Library tab organizes every
     built-in scene by category, in addition to the featured Discover view and your
     imported videos."
3. Keep `Scene.all` ordering stable (append new scenes at the end) so saved
   `selected`/`active` ids in `UserDefaults` keep resolving to the same names for
   existing users — never reuse an old scene's `id` or `kind` for a different scene.

## 5. Acceptance criteria

- [ ] `Scene` has a `category` field; all scenes (existing and new) are tagged.
- [ ] The catalog has grown beyond the original six scenes (target: 16+).
- [ ] The Library window shows three sidebar sections: Discover, Library, My videos.
- [ ] The Library section supports filtering by category and by the existing search
      field, and correctly shows an empty/all state.
- [ ] Every scene in `Scene.all` renders and animates per `Tests/RenderSmoke.swift`
      (`bash scripts/test.sh` passes).
- [ ] `bash scripts/build.sh` still produces `build/Driftwall.app` without warnings
      introduced by this change.
- [ ] README reflects the new scene count and the Library tab.
- [ ] No existing scene's `id` or `kind` changed (backward compatible with saved
      preferences).

## 6. Non-goals (do not do these as part of this change)

- No network calls, wallpaper marketplaces, or remote asset downloads — Driftwall is
  offline-only by design (see README "Scope and limitations").
- No new third-party dependencies.
- No changes to video import/removal behavior.
- No Lock Screen / screen saver integration.
