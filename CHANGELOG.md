## 2.1.4
- Subjob inference now self-corrects when a job-exclusive observed spell or ability conflicts with stale inferred/remote metadata; local live subjob remains authoritative.
- Non-Compact HUD status row now shows `Sort:` after `Filter:` with the active target and `H-L`/`L-H` direction.


- Expanded passive Job/Sub inference without changing raw combat capture. The support-job ceiling is treated as level 59 for Master Level characters.
- Added support-job evidence from unique spells and safe job-specific abilities, including Gravity -> /RDM, Sublimation/Light Arts -> /SCH, Waltz/Jig families -> /DNC and Jump -> /DRG when the known main job differs.
- Added conservative Reraise disambiguation: observed Scholar state wins /SCH; otherwise a non-WHM/non-SCH main may infer /WHM at lower confidence and later stronger evidence can correct it.
- The local player row now uses blue as a secondary/default row color. Existing semantic colors remain primary and are not overwritten.
- Added universal Show/Hide and Include/Exclude controls for visible fields, categories and named detail actions across all Views.
- Show/Hide affects presentation only; Include/Exclude changes calculated output while preserving raw captured combat data.
- Named WS exclusions recalculate WS damage, attempts, hits, misses, averages, total damage, DPS, sorting and reports without deleting the underlying action data.
- Named spell/recovery exclusions now flow through detail rows and adjusted aggregate calculations where the parser retains per-action counters.
- Separated `Melee` from the broader `Physical` group: Melee controls melee only; Physical intentionally groups Melee + WS + Skillchain.
- Standardized Defense magical damage-taken label as `MagicT`.
- Preserved Perfect Dodge forced-miss filtering so melee misses during the observed Perfect Dodge window do not lower Accuracy.
- Repeated Sort on the same category, subcategory, metric or named action now reverses High-to-Low / Low-to-High; explicit `asc` / `desc` is also accepted.
- Explicit Sort clears pins so visible row order matches the requested ranking.
- Added hierarchical Sort targets using the same control namespace as Show/Hide and Include/Exclude.
- Added selective bold rendering for the title, command/status labels and table header rows using one masked companion object per HUD rather than per-cell overlays.
- Expanded Job/Sub inference from observed job-exclusive spells and abilities, including Gravity -> /RDM, Sublimation/Light Arts -> /SCH, DNC Waltz/Jig families -> /DNC, Jump -> /DRG and conditional Reraise -> /WHM or /SCH.

# VanaParse Standalone Changelog

## 2.1.3 - Confirmed fonts and command flexibility

- Font selection is strict: only fonts confirmed in-game to preserve VanaParse fixed-column alignment are accepted.
- Confirmed approved fonts: Consolas, Courier New, Cascadia Code and Lucida Console.
- Removed/rejected DejaVu Sans Mono, Cousine, Liberation Mono, PT Mono and Go Mono after in-game testing showed they collapse the parser table.
- `//vp font list` shows the approved fonts. Unsupported font names are rejected without changing the active HUD font.
- Restored Sort to Help and Settings menus.
- `show` / `hide` accept recognized parser categories and common column controls regardless of current View, including reversed forms such as `//vp acc hide`.
- Joined/reversed View names such as `//vp view wsdetails` and `//vp wsdetails view` resolve directly.
- Bare `//vp view` cycles only Compact → Dynamic → Full → Physical → WS, then stops and lists all View choices.

## 2.1.2 - Clean parser-only rebuild

- Rebuilt directly from the last known-good pre-split VanaParse 2.1.1 source.
- Removed Points, Progression, Scan, Limbus tracking and all unsupported/dead settings, handlers, commands and compatibility stubs associated only with those systems.
- Kept supported combat parser functionality, reports, filters, pins, job metadata, profiles and secondary HUD behavior.
- Preserved the stable pre-split single-text-object HUD renderer and existing font path without redesign.
- Verified the canonical View cycle: Compact, Dynamic, Full, Physical, WS, WS Details, Ranged, Magic, Magic Details, Pet, Healing, Healing Details, Recovery, Recovery Details and Defense.
- Verified Dynamic retains its stable core with an 18-column maximum and data-driven optional columns.
- Added comma formatting to WS hit/miss counts at 10,000 and above while preserving ungrouped values below 10,000.
- Verified enemy Perfect Dodge creates a forced-miss window: melee misses during the observed window are excluded from Accuracy attempts/misses by default while combat Active time continues.
- `//vp default` performs a hard visual reset: current VanaParse HUD primitives are destroyed, canonical defaults are restored in place, fresh HUD primitives are created and the clean state is saved.
- Named saved settings remain preserved independently of the active/default configuration.
- Preserved the existing VanaParse help/menu command structure while adding color-coded chat presentation.
- Help/menu labels and literal `//vp` commands use green, selectable options/current values use blue, and descriptions/separators use white.
- Help/menu coloring uses Windower chat color controls only and does not alter parser HUD rendering, fonts, table layout or combat logic.
- No font whitelist or font-rendering redesign is included in this release.

### 2.1.4 Command Dispatcher Repair
- Restored command branches accidentally dropped during the universal-control merge: `view`, `mode/scope`, `filter/unfilter`, `set`, and `performance/stat/stats`.
- Preserves 2.1.4 universal Show/Hide/Include/Exclude/Sort behavior, self-correcting Subjob inference, Sort status display, fonts, rendering, and parser logic unchanged.
