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
