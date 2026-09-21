# VanaParse 2.1.4 Command Directory

**English is authoritative.** Japanese guidance follows each major section where practical.

This file documents the user-facing command grammar implemented in VanaParse 2.1.4. Commands are case-insensitive unless a player, enemy, profile or font name is being supplied.

**英語版を正式な仕様とします。** 各主要セクションに日本語の案内を併記しています。

---

## 1. Universal command grammar

VanaParse uses the same command behavior wherever the target supports it:

- A true **On/Off feature** toggles when used by itself: `//vp job`, `//vp wsavg`.
- A finite **selector** cycles when used by itself. Bare `//vp view` cycles Compact → Dynamic → Full → Physical → WS, then stops and lists all Views. `//vp mode`, `//vp theme` and `//vp sort` continue cycling normally.
- Common On words: `on`, `show`, `enable`, `enabled`, `true`, `1`, `add`.
- Common Off words: `off`, `hide`, `disable`, `disabled`, `false`, `0`, `remove`.
- Explicit toggle: `toggle`.
- Inspect without changing: `status`, `state`, `setting`, `settings` where supported.
- Restore feature default: `default`, `reset` where supported.
- Unique shorthand is accepted when it cannot collide with an older command. Example: `//vp dynamic`, `//vp wsdetails`, `//vp dark`, `//vp contrast dark`.
- Joined View names are accepted: `wsdetails`, `magicdetails`, `healingdetails`, `recoverydetails`.
- Natural reversed order is accepted when unambiguous: `//vp wsdetails view`, `//vp acc hide`, `//vp ws show`.
- Canonical syntax is preferred. Obsolete View names are migrated from saved settings at load and are not retained as user-facing commands.

VanaParse は可能な限り同じ command grammar を使用します。On/Off feature は bare command で toggle、View/Mode/Theme/Sort のような selector は bare command で cycle します。

---

## 2. Help, Status, Settings, Version and Health

### Main help

```text
//vp help
//vp ?
//vp help all
```

### Section help

```text
//vp help view
//vp help hud
//vp help mode
//vp help filter
//vp help session
//vp help report
//vp help reports
//vp help split
//vp help local
//vp help pin
//vp help pins
//vp help setup
//vp help theme
//vp help font
//vp help save
//vp help saved
//vp help profiles
//vp help command
//vp help commands
```

Reversed help is accepted for categories handled by the hierarchy:

```text
//vp view help
//vp mode help
//vp theme help
```

### Version

```text
//vp version
```

Outputs only the installed VanaParse version, for example:

```text
VanaParse: Version 2.1.4
```

The generic and section Help headers also include the current version. `version` has no subcommands and does not change any setting.

### Live status

```text
//vp status
```

Shows current operational state, location, View, Mode, Filter, timers, actor count, WS Avg, Pins, secondary HUD state, report setup, theme, background and font.

### Persistent settings

```text
//vp settings
//vp setting
//vp config
//vp configuration
```

Specific sections:

```text
//vp settings view
//vp settings hud
//vp settings mode
//vp settings filter
//vp settings filters
//vp settings report
//vp settings reports
//vp settings theme
//vp settings font
//vp settings size
//vp settings local
//vp settings pin
//vp settings pins
//vp settings save
//vp settings saved
//vp settings profiles
//vp settings idle
//vp settings session
```

### Health

```text
//vp health
```

Shows VanaParse protected error counters and whether the parser is currently Good or Degraded. A secondary HUD can disable itself after repeated rendering failures while the main parser continues.

`//vp health` は protected error counter と parser health を表示します。

---

## 3. HUD visibility and secondary HUDs

### Main HUD

Bare command toggles:

```text
//vp hud
//vp hud main
```

Explicit:

```text
//vp hud main on
//vp hud main off
//vp hud main show
//vp hud main hide
//vp hud main toggle
//vp hud main status
//vp show hud
//vp hide hud
```

### All HUD

```text
//vp hud all
//vp hud all on
//vp hud all off
//vp hud all show
//vp hud all hide
//vp hud all toggle
//vp hud all status
```

View:

```text
//vp hud all view
//vp hud all view compact
//vp hud all view dynamic
//vp hud all view full
//vp hud all view physical
//vp hud all view ws
//vp hud all view ws details
//vp hud all view ranged
//vp hud all view magic
//vp hud all view magic details
//vp hud all view pet
//vp hud all view healing
//vp hud all view healing details
//vp hud all view recovery
//vp hud all view recovery details
//vp hud all view defense
```

Bare `//vp hud all view` cycles that HUD's View.

Rows:

```text
//vp hud all rows 12
//vp hud all rows all
//vp hud all rows default
```

### All Parties HUD

Accepted names: `allparties`, `allparty`, `allpartys`.

```text
//vp hud allparties
//vp hud allparties on
//vp hud allparties off
//vp hud allparties show
//vp hud allparties hide
//vp hud allparties toggle
//vp hud allparties status
//vp hud allparties view
//vp hud allparties view dynamic
//vp hud allparties rows 12
//vp hud allparties rows all
//vp hud allparties rows default
```

`All` is the broad current-encounter scope. `All Parties` is the nearby observed-encounter mode and does not require local claim or Party/Alliance membership.

---

## 4. View / HUD data layout

Bare View cycles only through the primary sequence `Compact → Dynamic → Full → Physical → WS`. At WS it stops and prints the full View list:

```text
//vp view
```

Explicit Views:

```text
//vp view compact
//vp view dynamic
//vp view full
//vp view physical
//vp view ws
//vp view ws details
//vp view ranged
//vp view magic
//vp view magic details
//vp view pet
//vp view healing
//vp view healing details
//vp view recovery
//vp view recovery details
//vp view defense
```

Joined and reversed equivalents are accepted where unambiguous:

```text
//vp view wsdetails
//vp wsdetails view
//vp magicdetails
```

Canonical command variants are case-insensitive. `WS`, `Weapon Skill` and `Weaponskill` resolve to the same View, and `WS Details`, `Weapon Skill Details` and `Weaponskill Details` resolve to the same detailed View.

Unique top-level shortcuts include:

```text
//vp compact
//vp dynamic
//vp full
//vp ws details
//vp weapon skill details
//vp magic details
//vp healing details
//vp recovery details
```

Bare category words such as `magic`, `ranged`, `healing`, `pet` and `ws` retain their display-toggle meaning where that older command is still a current feature. Use `//vp view <name>` to select the View explicitly.

Compact defaults to `Job`; other Views default to `Job/Sub` when Job is Auto.

---

## 4A. Display category visibility

Show/Hide is independent of the current View. The setting is remembered and is applied anywhere that category or column exists.

```text
//vp show acc
//vp hide acc
//vp acc show
//vp acc hide
//vp show wsacc
//vp hide wshm
//vp show physical
//vp hide magic
```

Recognized display items include `acc`, `racc`, `wsacc`, `wshm`, `wsavg`, `physical`, `ws`, `sc`, `magic`, `mb`, `ranged`, `pet`, `healing`, `recovery`, `defense` and `crits`.

The focused specialized View remains selectable even when a composite-display category is hidden. Visibility rules primarily control the columns/sections where that category is part of a multi-category layout.

---

## 5. Mode / actor scope

Bare Mode cycles:

```text
//vp mode
//vp scope
```

Explicit:

```text
//vp mode self
//vp mode local
//vp mode party
//vp mode alliance
//vp mode all
//vp mode allparties
//vp mode all parties
//vp mode custom
```

`scope` is an alias:

```text
//vp scope party
//vp scope all
//vp scope all parties
```

Top-level unique shortcuts:

```text
//vp self
//vp party
//vp alliance
//vp allparties
//vp allparty
//vp allpartys
//vp custom
```

`local` remains the Local-character-management command and is therefore not hijacked as a Mode shorthand. Use `//vp mode local`.

Set syntax remains available:

```text
//vp set scope self
//vp set scope local
//vp set scope party
//vp set scope alliance
//vp set scope all
//vp set scope allparties
//vp set scope custom
```

---

## 6. All Parties observed encounter focus

```text
//vp observe target
//vp observe current
//vp observe next
//vp observe previous
//vp observe prev
//vp observe <enemy name>
```

Example:

```text
//vp observe SharedBoss
```

This selects which nearby observed encounter feeds `All Parties` when multiple fights are visible.

---

## 7. Enemy and damage Filter

### Status

```text
//vp filter
//vp filter status
//vp filter list
```

### Current target

```text
//vp filter target
//vp filter current
//vp unfilter target
//vp unfilter current
```

### Enemy text filter

```text
//vp filter EnemyA
//vp filter SharedBoss
//vp unfilter EnemyA
```

Multiword enemy names are accepted.

### Clear all filters

```text
//vp filter clear
//vp filter reset
//vp filter all
//vp unfilter clear
//vp unfilter reset
//vp unfilter all
```

These clear enemy filters and restore all damage-category filters.

### Damage filter examples

```text
//vp filter physical
//vp filter melee
//vp filter ranged
//vp filter ws
//vp filter sc
//vp filter magic
//vp filter pet
//vp filter petmagic
//vp unfilter magic
```

`unfilter <damage category>` restores damage filtering to all categories.

---


## 8. Job and Subjob display

### Job

Aliases: `job`, `jobs`.

```text
//vp job
//vp job on
//vp job off
//vp job show
//vp job hide
//vp job toggle
//vp job auto
//vp job status
//vp job state
//vp job settings
//vp job default
//vp job reset
//vp show job
//vp hide job
```

### Subjob

Aliases: `sub`, `subjob`, `subjobs`.

```text
//vp sub
//vp sub on
//vp sub off
//vp sub show
//vp sub hide
//vp sub toggle
//vp sub auto
//vp sub status
//vp sub default
//vp sub reset
//vp show sub
//vp hide sub
//vp show subjob
//vp hide subjob
```

Auto behavior:

- Compact: `Job`
- Other Views: `Job/Sub`

---

## 9. WS Avg, Highlights and Crits

### WS Avg

Aliases: `wsavg`, `wsaverage`, `weaponskillavg`.

```text
//vp wsavg
//vp wsavg on
//vp wsavg off
//vp wsavg show
//vp wsavg hide
//vp wsavg toggle
//vp wsavg status
//vp wsavg default
//vp wsavg reset
//vp show wsavg
//vp hide wsavg
//vp show ws average
//vp hide ws average
//vp set wsavg on
//vp set wsavg off
```

### Highlights

```text
//vp highlights
//vp highlight
//vp highlights on
//vp highlights off
//vp highlights show
//vp highlights hide
//vp highlights toggle
//vp highlights status
//vp highlights default
//vp highlights reset
```

### Crits

```text
//vp crits
//vp crit
//vp critical
//vp crits on
//vp crits off
//vp crits show
//vp crits hide
//vp crits toggle
//vp crits status
//vp crits default
//vp crits reset
```

---

## 10. Display-category toggles

These are On/Off display controls, not View selectors when used bare.

### Physical

```text
//vp physical
//vp melee
//vp attack
```

### Magic

```text
//vp magic
//vp magical
//vp spell
//vp spells
```

### Magic Burst

```text
//vp mb
```

### Ranged

```text
//vp ranged
//vp range
//vp shoot
//vp shooting
//vp ra
```

### Healing

```text
//vp healing
//vp heal
//vp cure
//vp curing
//vp waltz
//vp walz
```

### Recovery

```text
//vp recovery
//vp cleanse
```

### Defense

```text
//vp defense
//vp def
```

### Pet

```text
//vp pet
//vp automaton
//vp wyvern
//vp jug
//vp avatar
//vp luopan
```

### Weapon Skill

```text
//vp ws
//vp weaponskill
```

### Skillchain

```text
//vp sc
//vp skillchain
```

Each supports standard On/Off words, e.g.:

```text
//vp magic
//vp magic on
//vp magic off
//vp magic show
//vp magic hide
//vp magic toggle
//vp magic status
//vp magic default
```

---

## 11. Universal Show / Hide / Add / Remove

```text
//vp show <field|category|action>
//vp hide <field|category|action>
//vp add <field|category|action>
//vp remove <field|category|action>
//vp <subject> show
//vp <subject> hide
```

Every visible column in every View is addressable by its displayed name or a sensible alias, including Low, Avg, Peak/High, Parry, Evade, Block, CureAvg, WS Acc and similar fields. Named detail actions are also addressable after they have appeared in the parse, e.g. `//vp hide Savage Blade` or `//vp Cure hide`.

Whole categories remain addressable: Melee, Physical, WS, SC, Magic, MB, Ranged, Pet, Healing, Recovery and Defense. `Melee` means melee only. `Physical` intentionally groups Melee + WS + Skillchain.

Information-only Show commands:

```text
//vp show status
//vp show filters
//vp show pins
//vp show splits
```

---

## 12. Universal Include / Exclude

```text
//vp include <field|category|action>
//vp exclude <field|category|action>
//vp <subject> include
//vp <subject> exclude
```


Include/Exclude never deletes raw captured events. Excluding a named detail action recalculates affected aggregate results from the retained raw action counters. For example, `//vp exclude Savage Blade` removes Savage Blade from combined WS damage, attempts, hits, misses, averages, DPS/total-damage contribution, sorting and WS detail/report calculations until it is included again. Pure display statistics such as Low or Peak are omitted when excluded and can be restored with Include.

Trusts:

```text
//vp include trust
//vp include trusts
//vp exclude trust
//vp exclude trusts
```

Allied NPCs:

```text
//vp include ally
//vp include allies
//vp include allied
//vp include allied npc
//vp include allied npcs
//vp exclude allied npcs
```

All damage categories:

```text
//vp include all
//vp exclude all
```

Damage categories and aliases include:

```text
melee / physical
ranged / range
ws
sc / skillchain
magic
other
pet
petmelee / pet-melee / pmelee
petranged / pet-ranged / pranged
petphysical / pet-physical / pphys
petmagic / pet-magic / pmagic
petsc / pet-sc / psc
```

---

## 13. Target line

```text
//vp show target
//vp hide target
//vp set target on
//vp set target off
//vp set target auto
```

---

## 14. Actor rows

Main HUD:

```text
//vp set rows 12
//vp set row 12
//vp set rows all
//vp set rows off
//vp set rows default
//vp set rows reset
```

`all`/`off` means no row cap, not hide the HUD.

Secondary HUDs use `//vp hud all rows ...` and `//vp hud allparties rows ...`.

---

## 15. Sort

Bare cycles:

```text
//vp sort
```

Explicit values:

```text
//vp sort party
//vp sort damage
//vp sort dps
//vp sort melee
//vp sort accuracy
//vp sort acc
//vp sort ranged
//vp sort racc
//vp sort ws
//vp sort wsacc
//vp sort wsavg
//vp sort sc
//vp sort magic
//vp sort pet
//vp sort healing
//vp sort recovery
//vp sort cleanse
//vp sort cleanses
//vp sort dispel
//vp sort dispels
//vp sort taken
```

`recovery` normalizes to the Recovery/Cleanse sort.

---

## 16. Reports: core model

Canonical form:

```text
//vp report [metric] [view] [player/enemy] [scope] [split] [destination]
```

Most report tokens are classified by meaning rather than rigid position. `rep` is accepted as a short form for `report`.

### View report meaning

A View name inside a report means **report every statistic defined by that View** for every applicable actor, independent of the HUD's visible row cap.

```text
//vp report compact
//vp report dynamic
//vp report physical
//vp report magic
//vp report ranged
//vp report healing
//vp report pet
//vp report ws
```

`//vp report view` and `//vp report hud` use the currently selected View.

`//vp report all` means all actors and all metrics in the selected/current View.

Examples:

```text
//vp report compact party
//vp report dynamic alliance
//vp report all party
```

### Metric + View

A metric narrows a View report to only that statistic:

```text
//vp report accuracy compact party
//vp report compact accuracy party
//vp report wsavg dynamic party
//vp report dps compact alliance
```

`//vp report accuracy compact party` means: Accuracy for every applicable actor in Compact context, sent to Party.

### Specific player

A player name narrows the report to that actor. The player does not have to be one of the currently visible HUD rows; VanaParse uses the underlying retained parse data.

```text
//vp report compact PlayerA party
//vp report accuracy compact PlayerA party
//vp report PlayerA accuracy compact party
```

### Subject / enemy

When leftover subject text does not resolve to an actor, it is used as enemy-filter text for that report source.

```text
//vp report magic SharedBoss alliance
```

Use explicit actor scope when needed to avoid ambiguity.

---

## 17. Report Views

A View name means “report the metrics defined by that View.” Supported View contexts are:

```text
compact
dynamic
full
physical
ws
ws details
ranged
magic
magic details
pet
healing
healing details
recovery
recovery details
defense
```

Examples:

```text
//vp report compact party
//vp report accuracy compact party
//vp report compact accuracy party
//vp report dynamic PlayerA party
//vp report ws details PlayerA self
//vp report magic details SharedBoss alliance
```

A metric narrows the selected View. A player name narrows the report to that actor even if that actor is outside the currently visible HUD rows, provided VanaParse retained data for that actor.


## 18. Report metric selectors

Single-word metric aliases currently include:

```text
accuracy / acc / meleeacc / melee-acc
dps
damage / dmg / totdmg / tot-dmg
share / percent / percentage / percentages / % / totdmgpercent / tot-dmg%
melee
ranged
racc
magic
pet
healing / cured
wsdamage / ws-dmg
wsavg / wsaverage
wsacc / ws-acc
wshm / ws-hm
sc / skillchain
mb
recovery / cleanse
taken / defense
```

Multiword metrics:

```text
weapon skill average
weapon skill accuracy
weapon skill damage
weapon skill hit/miss
melee accuracy
total damage percent
tot dmg %
```

Examples:

```text
//vp report melee accuracy compact party
//vp report weapon skill average dynamic alliance
```

---

## 19. Legacy report categories

These remain supported when used without an explicit View-metric combination:

```text
view / hud
full
dps / damage / dmg / offense
physical / melee / attack
ws / weaponskill
sc / skillchain
magic / magical / spell / spells
mb / magic burst / magic bursts
ranged / range / shoot / shooting / ra / ranged attack
healing / heal / cure / curing / waltz / curing waltz
recovery / status / cleanse / status recovery / remove status / healing waltz
defense / def
pet / automaton / wyvern / jug / avatar
pet physical / pet melee
pet magic / pet magical
pet ranged / pet range / pet shooting
pet healing / pet cure
percent / percentage / percentages / %
performance / perform / stat / stats
```

`full` remains the exhaustive legacy category report. `all` means all metrics in the selected/current View.

---

## 20. Report actor scope

Use an explicit marker when specifying whose actors are included:

```text
scope
mode
actors
from
```

Values:

```text
self
local
party
alliance
all
allparties
all parties
```

Examples:

```text
//vp report compact scope party self
//vp report accuracy compact scope all party
//vp report dynamic from all parties alliance
```

Note: a bare `party` or `alliance` token inside a report normally means report **destination**. Use `scope party` or `from party` when you mean actor scope.

---

## 21. Report destinations

Approved destinations:

```text
hud
self
local
console
party / p
alliance / a
linkshell / l / l1
linkshell2 / l2
tell / t <player>
```

Explicit destination markers:

```text
to
send
destination
channel
```

Examples:

```text
//vp report compact to party
//vp report accuracy dynamic send alliance
//vp report ws destination linkshell
//vp report full to tell PlayerB
```

Persistent destination:

```text
//vp set report hud
//vp set report self
//vp set report party
//vp set report alliance
//vp set report linkshell
//vp set report linkshell2
//vp set report tell PlayerB
```

Legacy destination setup forms remain:

```text
//vp report set party
//vp report mode party
//vp report destination party
//vp report channel party
```

### Blocked public channels

VanaParse rejects report output to:

```text
say / s
yell / y
shout / sh
unity
assist
jp
en
eu
```

---

## 22. Report delay and default content

```text
//vp set delay 1.05
//vp set report delay 1.05
```

Allowed delay range: `0.10` to `3.00` seconds per queued report line.

Default report content:

```text
//vp set report content view
//vp set report content full
//vp set report content physical
//vp set report content ws
//vp set report content magic
//vp set report content ranged
//vp set report content pet
//vp set report content healing
//vp set report content recovery
//vp set report content defense
//vp set report content percent
```

---

## 23. Report Split intervals

```text
//vp report split 1
//vp report split 1-2
//vp report split 1 physical party
//vp report split 1-2 magic alliance
//vp report accuracy compact split 1-2 party
```

`split 1` means Split 1 through current/end. `split 1-2` means only the interval between the two split boundaries.

---

## 24. Performance report

Aliases: `performance`, `stat`, `stats`.

```text
//vp performance
//vp performance PlayerA
//vp stats PlayerB
//vp performance all
//vp performance PlayerA all
```

Without a player name, the local player is used. `all` requests exhaustive detail.

---

## 25. Splits

Start a sequential split:

```text
//vp split
```

Named split:

```text
//vp split Phase 1
```

Manage:

```text
//vp split list
//vp split status
//vp split show 1
//vp split show Phase 1
//vp split current
//vp split delete 1
//vp split delete Phase 1
//vp split clear
//vp unsplit
```

---

## 26. Local characters

```text
//vp local
//vp local show
//vp local list
//vp local add PlayerA
//vp local add PlayerA PlayerB PlayerC
//vp local remove PlayerB
//vp local clear
```

Local is a saved actor grouping used by `Mode: Local` and Local pinning.

---

## 27. Pins

```text
//vp pin self
//vp pin local
//vp pin party
//vp pin alliance
//vp pin PlayerA
//vp pin PlayerA 1
//vp unpin self
//vp unpin local
//vp unpin party
//vp unpin alliance
//vp unpin PlayerA
//vp unpin all
//vp pin default
//vp unpin default
```

Natural reversed order:

```text
//vp self pin
//vp self unpin
//vp local pin
//vp local unpin
//vp party pin
//vp party unpin
//vp alliance pin
//vp alliance unpin
```

Pinning changes presentation only. True statistical rank remains unchanged.

---

## 28. Theme

Bare cycles:

```text
//vp theme
```

Cycle:

```text
dark -> light -> contrastdark -> contrastlight -> dark
```

Explicit:

```text
//vp theme dark
//vp theme light
//vp theme contrastdark
//vp theme contrastlight
//vp theme contrast dark
//vp theme contrast light
```

Shortcuts:

```text
//vp dark
//vp light
//vp contrastdark
//vp contrastlight
//vp contrast dark
//vp contrast light
//vp hc
//vp highcontrast
```

`inverse` legacy shortcut:

```text
//vp inverse
```

Contrast themes default to `80%` background opacity (`20%` transparency) and remember a separate contrast opacity from normal Dark/Light.

---

## 29. Background opacity

Aliases: `bg`, `background`, `opacity`.

Status:

```text
//vp bg
//vp background
//vp opacity
```

Set:

```text
//vp bg 76
//vp bg 76%
//vp background 43.5
//vp opacity 80%
//vp set bg 76%
//vp set background 76
//vp set opacity 76
```

Range: `0` to `100`. This changes background opacity only; Theme controls palette/text/background colors.

---

## 30. Font and font size

Font status:

```text
//vp font
//vp font status
```

Font family:

```text
//vp font Consolas
//vp font Courier New
//vp font list
//vp font Arial
//vp set font Consolas
```

Size:

```text
//vp font size 5
//vp font size 5.25
//vp font size 5.5
//vp font size 5.75
//vp font size 6
//vp fontsize 6.25
//vp size 9
//vp set size 9.75
```

Range: `5.0` to `36.0`. Input is normalized to the nearest `0.25` point.

---

## 31. HUD position and dragging

Main HUD position:

```text
//vp set position 470 150
//vp set pos 470 150
```

Dragging:

```text
//vp lock
//vp unlock
```

Secondary HUD positions are independently retained through their HUD settings.

---

## 32. Pause, Resume and Reset

Pause aliases:

```text
//vp pause
//vp stop
```

Resume aliases:

```text
//vp resume
//vp continue
//vp start
```

Full parser/session reset:

```text
//vp reset
//vp clear
```

---

## 33. Saved Settings profiles

Save:

```text
//vp save Multibox
//vp save setting Multibox
//vp save settings Multibox
```

Multiword names are accepted:

```text
//vp save Alliance Event
```

Restore:

```text
//vp restore Multibox
```

List:

```text
//vp saves
//vp saved
```

Delete:

```text
//vp delete setting Multibox
//vp delete settings Multibox
//vp delete profile Multibox
```

Built-in defaults:

```text
//vp default
```

One-step return after the most recent profile restore/default operation:

```text
//vp return
```

Save current settings and learned enemy registry immediately:

```text
//vp save
```

Profiles store behavior/settings, not active combat totals, targets or current encounter data.

---

## 34. Reload and unload

```text
//vp reload
//vp unload
```

VanaParse saves settings before issuing the Windower reload/unload command.

---

## 35. `set` command summary

The explicit legacy `set` namespace remains available:

```text
//vp set rows <1-99|all|off|default|reset>
//vp set delay <0.10-3.00>
//vp set report delay <0.10-3.00>
//vp set scope <self|local|party|alliance|all|allparties|custom>
//vp set report <hud|self|tell <name>|party|alliance|linkshell|linkshell2>
//vp set report content <content>
//vp set font <font name>
//vp set size <5-36>
//vp set position <x> <y>
//vp set pos <x> <y>
//vp set bg <0-100|0-100%>
//vp set background <0-100|0-100%>
//vp set opacity <0-100|0-100%>
//vp set theme <dark|light|contrastdark|contrastlight|contrast dark|contrast light>
//vp set target <on|off|auto>
//vp set wsavg <on|off>
```

---

## 36. Examples of composable reporting

All Compact View metrics for all applicable actors to Party:

```text
//vp report compact party
```

Accuracy only for all applicable actors in Compact context:

```text
//vp report accuracy compact party
//vp report compact accuracy party
```

Compact View metrics for one player, even if outside the current visible row cap:

```text
//vp report compact PlayerA party
```

Accuracy only for one player:

```text
//vp report accuracy compact PlayerA party
//vp report PlayerA accuracy compact party
```

Dynamic View using All actor scope, sent to Party:

```text
//vp report dynamic scope all party
```

Accuracy in Compact View from All Parties actor scope, sent to Alliance:

```text
//vp report accuracy compact scope all parties alliance
```

Magic legacy category report against a named enemy:

```text
//vp report magic SharedBoss alliance
```

View metric over a split interval:

```text
//vp report accuracy compact split 1-2 party
```

---

## 37. Safety notes

- Report output never uses public/broadcast channels.
- HUD DPS display refresh is throttled to 5 seconds by default, but report DPS calculations use exact current data.
- Transition guards pause unsafe entity-dependent work during zoning and large in-zone teleports.


