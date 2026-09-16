# VanaParse Standalone 2.1.4

VanaParse is a real-time Final Fantasy XI combat parser for Windower 4. Version 2.1.4 continues the clean parser-only rebuild from the last known-good pre-split source. This release contains only supported combat-parser functionality and no inactive legacy feature settings or command stubs.

VanaParse は Windower 4 用のリアルタイム Final Fantasy XI 戦闘解析アドオンです。Version 2.1.4 は、最後に安定していた split 前の source を基準にした clean parser-only rebuild を継続します。この release には supported combat-parser functionality のみを含み、inactive legacy feature setting や command stub は含みません。

**Author:** Errorist of Vana'diel  
**License:** MIT  
**Version:** 2.1.4  
**Embedded VanaCore:** 0.3.3.1

## Install / インストール

Copy the included `VanaParse` folder over `Windower4/addons/VanaParse/`, then reload with `//lua r VanaParse` or restart Windower.

同梱の `VanaParse` folder を `Windower4/addons/VanaParse/` に上書きし、`//lua r VanaParse` または Windower の再起動で再読み込みします。

This clean release does not include generated `settings.xml`, combat logs or learned runtime data. Compatible existing settings are migrated automatically.

この clean release には生成済み `settings.xml`、combat log、learned runtime data は含まれません。互換性のある既存 setting は自動的に移行されます。

For the complete command reference, read **`COMMAND_DIRECTORY.md`** inside the VanaParse folder.

完全な command reference は VanaParse folder 内の **`COMMAND_DIRECTORY.md`** を参照してください。

## HUD model / HUD モデル

The main HUD can use `Self`, `Local`, `Party`, `Alliance`, `All`, `All Parties` or `Custom` mode. `All` includes observable contributors to the current encounter. `All Parties` is a nearby-fight observer that does not require your Party/Alliance to claim or establish the encounter.

Main HUD は `Self`、`Local`、`Party`、`Alliance`、`All`、`All Parties`、`Custom` mode を使用できます。`All` は current encounter の observable contributor を含み、`All Parties` は local claim を必要としない nearby-fight observer です。

Optional `All` and `All Parties` HUDs share the same underlying parser/action stream. They do not independently parse or duplicate damage.

```text
//vp hud all on
//vp hud allparties on
//vp hud all view compact
//vp hud allparties view dynamic
//vp hud all rows 12
//vp hud allparties rows all
```

Observed All Parties encounters remain separated. Use the target or observer controls to select the fight you want to inspect.

```text
//vp observe target
//vp observe next
//vp observe previous
//vp observe <enemy name>
```

## Header and parser rows / Header と parser row

The HUD header, target line and parser table remain on the stable pre-split rendering path. Only supported parser rows are rendered.

HUD header、target line、parser table は安定していた split 前の rendering path を維持し、supported parser row のみを表示します。

`Zone:` is intentionally omitted from the title. If a valid map position cannot be resolved, only the short zone name is displayed; VanaParse never displays `(?-?)`.

## Universal command grammar / 共通 command grammar

VanaParse uses one consistent grammar wherever practical:

- True On/Off features toggle when used alone, such as `//vp job` and `//vp wsavg`.
- Bare `//vp view` cycles Compact → Dynamic → Full → Physical → WS, then stops and lists all Views. `//vp mode`, `//vp theme` and `//vp sort` cycle normally.
- `on/show/enable` mean On.
- `off/hide/disable` mean Off.
- `toggle` explicitly toggles.
- `status/state/settings` inspect without changing where supported.
- `default/reset` restores that feature's default where supported.
- Unique shorthand is accepted when it cannot collide with older commands, for example `//vp dynamic`, `//vp dark` and `//vp contrast dark`.
- Older explicit syntax remains valid.

既存 command を壊さないことを優先し、ambiguous shorthand は old behavior を保持します。たとえば bare `//vp magic` は従来どおり Magic display toggle で、Magic View を選ぶ場合は `//vp view magic` を使用します。

## View, Mode and Filter

Bare selectors cycle:

```text
//vp view
//vp mode
//vp theme
//vp sort
```

Explicit View examples:

```text
//vp view compact
//vp view dynamic
//vp view physical
//vp view magic
//vp view ranged
//vp view healing
//vp view pet
//vp view ws
```

Joined and natural-order forms are also accepted:

```text
//vp view wsdetails
//vp wsdetails view
//vp acc hide
//vp show acc
```

`show` and `hide` operate on recognized parser categories/columns regardless of the current View. Supported common aliases include `acc`, `racc`, `wsacc`, `wshm`, `wsavg`, `physical`, `ws`, `sc`, `magic`, `ranged`, `pet`, `healing`, `recovery` and `defense`.


Enemy filtering remains a first-class feature:

```text
//vp filter
//vp filter target
//vp filter EnemyA
//vp unfilter EnemyA
//vp filter clear
```

`filter current` remains as a backward-compatible alias for `filter target`.

## Job / Subjob

Compact defaults to `Job`. Every other View defaults to `Job/Sub`. The entire Job column can be hidden.

When direct party/check metadata is unavailable, VanaParse can infer a support job conservatively from job-exclusive spells and abilities. Master-Level support jobs are treated as potentially reaching level 59, so actions available by level 59 are not used as main-job proof. Stronger later evidence can replace a lower-confidence inference.

Examples include a known WHM using Gravity -> `/RDM`, a known COR using Waltz/Jig actions -> `/DNC`, a known WAR using Jump -> `/DRG`, and Sublimation/Light Arts -> `/SCH`. Reraise is treated specially because SCH requires Scholar state/Addendum access; observed Scholar state wins `/SCH`, otherwise `/WHM` may be used as a lower-confidence passive inference until stronger evidence appears.

The local player's full parser row uses blue as a secondary/default row color. Existing semantic colors such as accuracy/performance highlights take priority over the blue row color.

```text
//vp job
//vp job on
//vp job off
//vp job auto
//vp sub on
//vp sub off
//vp sub auto
```

VanaParse uses direct Party/Alliance metadata when available, passive `/check` metadata received by the client and conservative job-exclusive action evidence. It does not automatically issue `/check` just to identify jobs.

## Active timer / Active timer

Active time measures battle participation, not merely whether a living enemy still exists.

- 0–29 seconds without qualifying activity: Active continues normally.
- At 30 seconds: the 30-second gap becomes provisional and the confirmed Active value rolls back once, for example `Active 00:10:20 +00:30 (Idle)`.
- Activity before 60 seconds: the provisional gap is restored into Active, briefly showing `(Restored XXs)`, and Active immediately continues counting.
- At 60 seconds: the idle minute is omitted and Active pauses, briefly showing `(Paused | Idle 60s Omitted)`.
- Activity after timeout: Active resumes from the last confirmed value and briefly shows `(Resumed)`.

## DPS display refresh

Combat actions and damage are recorded immediately. Reports use current exact DPS. The **HUD DPS value refreshes every 5 seconds by default** so the number is readable rather than changing every rendered frame.

Combat data は即時記録されます。Report は exact DPS を使用し、HUD 上の DPS 表示のみ default 5 秒ごとに refresh します。

## Reporting / Report

Report Views now mean the metrics defined by that View.

```text
//vp report compact
//vp report dynamic
//vp report view
```

`report view` uses the currently active View. `report compact` explicitly uses Compact metrics even if the HUD is currently Dynamic.

Metric selectors narrow a View:

```text
//vp report accuracy compact party
//vp report compact accuracy party
```

Both mean: report Accuracy for all applicable actors in Compact context and send it to Party.

A player name narrows the report to that actor even if the actor is outside the currently visible HUD rows, as long as VanaParse retained data for that actor:

```text
//vp report compact PlayerA party
//vp report accuracy compact PlayerA party
```

The complete composable report grammar, actor scopes, split syntax, destinations and aliases are documented in `COMMAND_DIRECTORY.md`.

Supported destinations are only HUD/Self, Tell, Party, Alliance, Linkshell and Linkshell2. Public/broadcast channels such as Say, Yell, Shout, Unity, Assist, JP, EN and EU are blocked.

## Themes, background and font / Theme、background、font

Themes:

```text
//vp theme dark
//vp theme light
//vp theme contrastdark
//vp theme contrastlight
//vp contrast dark
```

Contrast themes default to **80% opacity / 20% transparency** and remember their own background-opacity setting separately from normal Dark/Light.

Background changes opacity only:

```text
//vp bg 76
//vp bg 76%
//vp background 76%
//vp opacity 76%
```

Font family and quarter-point font sizes are supported:

```text
//vp font Consolas

Only in-game confirmed fixed-column fonts are accepted. VanaParse 2.1.4 approves Consolas, Courier New, Cascadia Code and Lucida Console; unsupported fonts are rejected without changing the HUD.
//vp font Courier New
//vp font list
//vp font size 6.25
//vp fontsize 6.5
//vp size 6.75
//vp set size 7
```

Font size is clamped to 5–36 points and normalized to the nearest 0.25 point.


### Universal Show, Hide, Include and Exclude

Every visible parser field, parser category and named action in a detail View can be addressed by the universal controls. Show/Hide changes presentation only. Include/Exclude changes the calculated readout without deleting raw captured combat data.

```text
//vp hide low
//vp show parry
//vp exclude Savage Blade
//vp include Savage Blade
//vp Cure hide
//vp melee exclude
//vp physical include
```

`melee` controls melee only. `physical` is the intentional grouped control for Melee + WS + Skillchain. Joined/reversed command forms remain supported when the request can be resolved unambiguously.

## Help, Status, Settings, Version and Health

Version only:

```text
//vp version
```

The command returns `VanaParse: Version 2.1.4`. Help headers also show the installed version.

```text
//vp help
//vp help view
//vp help mode
//vp help filter
//vp help reports
//vp help theme
//vp help font

//vp status
//vp settings
//vp settings <section>
//vp health
```

Help pages include `[State | Setting]` where applicable. `Status` describes current runtime state. `Settings` describes configuration. `Health` reports protected VanaParse error counters so command/runtime regressions can be detected without crashing the addon.

## Saved settings profiles / Saved settings profile

Named profiles save behavior/settings, not combat totals, targets, splits or temporary encounter state.

```text
//vp save multibox
//vp save settings multibox
//vp restore multibox
//vp saves
//vp delete setting multibox
//vp default
//vp return
```

`//vp default` restores built-in behavior defaults while preserving named profiles. `//vp return` is a one-step runtime return to the configuration used immediately before the most recent profile restore/default operation.

## Stability model / Stability model

VanaParse 2.1.4 retains the 2.1.1 fail-closed parser model: missing, stale or transitional data should be skipped rather than treated as fatal.

- Full-zone and large in-zone teleport transition guards.
- Protected action, packet, command, zone, load/login, prerender and unload paths.
- Generation checks and transient-state clearing across transitions.
- Secondary-HUD circuit breakers isolate repeated HUD failures from the main parser.
- Observer encounters are bounded and expire when stale.
- Combat logs are batch-written and learned registry saves are throttled/deferred.
- A malformed or stale combat event may be dropped rather than allowed to stop VanaParse.

The FFXI client only supplies combat actions it actually receives, so `All` and `All Parties` mean all **observable** applicable participants, not every player everywhere in the zone.

## Semantic Versioning

Starting with 2.0.0, VanaParse uses `MAJOR.MINOR.PATCH` Semantic Versioning. Compatible feature releases increment MINOR, backward-compatible fixes increment PATCH and incompatible public behavior/configuration redesigns increment MAJOR.


CHANGE LOG - 16 Septemner 2026

## 2.1.4

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
