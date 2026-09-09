# VanaParse Standalone 1.1.3.0

VanaParse is a real-time Final Fantasy XI combat parser for Windower 4. It tracks alliance-wide combat performance while preserving detailed data for reports, filters, splits, target analysis, pets, magic, healing, recovery and defensive metrics.

VanaParse は Windower 4 用のリアルタイム Final Fantasy XI 戦闘解析アドオンです。Alliance 全体の combat performance を追跡し、report、filter、split、target analysis、pet、magic、healing、recovery、defensive metrics の詳細データを保持します。

**Author:** Errorist of Vana'diel  
**License:** MIT  
**Standalone version:** 1.1.3.0  
**Embedded VanaCore:** 0.3.3.1

**作者:** Errorist of Vana'diel  
**ライセンス:** MIT  
**Standalone バージョン:** 1.1.3.0  
**内蔵 VanaCore:** 0.3.3.1

## Upgrade / アップグレード

Copy the included `VanaParse` folder over your existing `Windower4/addons/VanaParse/` folder, then reload VanaParse with `//lua r VanaParse` or restart Windower.

同梱の `VanaParse` フォルダを既存の `Windower4/addons/VanaParse/` に上書きし、`//lua r VanaParse` または Windower の再起動で VanaParse を読み込み直します。

This release intentionally does **not** include `settings.xml` or the generated `data/` directory. Existing HUD position, size and compatible preferences therefore remain in place. Existing logs, learned enemy data and historical files are also left untouched.

この release には意図的に `settings.xml` と生成済み `data/` directory を含めていません。そのため既存の HUD position、size、互換性のある preference は保持されます。既存の logs、learned enemy data、historical files も上書きされません。

If a setting is newly introduced, VanaParse adds its default during configuration migration. The previous stock report delay of 0.65 seconds migrates to 1.05 seconds, while a user-selected custom delay is preserved.

新しく追加された setting は configuration migration 時に default が追加されます。従来の標準 report delay 0.65 秒は 1.05 秒に移行しますが、user が変更した custom delay は保持されます。

## Default Compact HUD / 標準 Compact HUD

Fresh installs start in Compact view.

新規 install は Compact view で開始します。

```text
VanaParse | Whitegate (J-7) | Elapsed 00:00:00 | Active 00:00:00
View: Compact | Mode: Alliance | Filter: None
Target: Aminon | HP: 111,111/333,333 (33%) | Incoming: Dancing Fullers

# | Player | Job | Tot Dmg % | Tot Dmg | DPS | Acc | WS H/M | WS Avg
```

When there is no target, the entire target row remains blank. The row is still reserved so the HUD does not repeatedly change height. A separate natural spacer remains before the parsing column headings.

Target がない場合、target row 全体は blank のままです。HUD の高さが頻繁に変化しないよう row 自体は保持され、parsing column heading の前には別の spacer も維持されます。

The metadata/header block is constrained to the parsing-table width. Variable target, filter and incoming-action text is shortened rather than widening the HUD.

Metadata/header block は parsing table の width を超えないよう制限されます。長い target、filter、incoming-action text は HUD を広げず短縮表示されます。

## Job and Subjob / Job と Subjob

The Job column is dynamic.

Job column は dynamic です。

```text
//vp job on       -> RDM
//vp sub on       -> RDM/DNC
//vp sub off      -> RDM
//vp job off      -> Job column removed
```

Natural aliases such as `jobs`, `subjob`, `show job`, `hide job`, `show sub` and `hide sub` are accepted.

`jobs`、`subjob`、`show job`、`hide job`、`show sub`、`hide sub` などの natural alias に対応します。

## Pinning and true rank / Pin と true rank

Pinning changes only visual placement. The `#` column always shows the actor's true rank according to the active sort metric. Reports also use the natural performance order rather than the pinned display order.

Pin は visual placement のみを変更します。`#` column は active sort metric に基づく true rank を常に表示し、report も pinned display order ではなく natural performance order を使用します。

Examples / 例:

```text
//vp pin self
//vp self pin
//vp unpin self
//vp pin local
//vp pin party
//vp pin alliance
//vp pin Errorist
//vp unpin Errorist
//vp unpin all
//vp pin default
```

`local` means the characters you identify as locally managed on that client. Self is always recognized as local.

`local` はその client で locally managed として指定した character を意味します。Self は常に local として認識されます。

```text
//vp local add Errorist Fubarist Bobsuruncle
//vp local remove Fubarist
//vp local show
//vp local clear
```

## Reporting / レポート

The default report queue delay is **1.05 seconds**.

標準 report queue delay は **1.05 秒** です。

Set the persistent destination once:

送信先は一度設定すれば保持されます。

```text
//vp set report party
//vp set report alliance
//vp set report self
//vp set report linkshell
//vp set report linkshell2
//vp set report tell PlayerName
```

Compact view omits `Report:` to preserve width. Larger views and `//vp status` can still show the saved destination.

Compact view では width を抑えるため `Report:` を省略します。Larger view と `//vp status` では saved destination を確認できます。

Report tokens are intentionally flexible. These forms can describe the same request:

Report token の順序は柔軟です。次のような command は同じ intent を表現できます。

```text
//vp report Papesse full party
//vp report full Papesse party
//vp Papesse report full party

//vp report Papesse magic party
//vp magic report Papesse party
```

A destination specified in one report overrides the saved destination for that report only.

個別 report で送信先を指定した場合、その report のみ saved destination を override します。

### Split reports / Split report

```text
//vp report split 1
```

Reports from Split 1 through the current end of the parse.

Split 1 から現在の parse end まで report します。

```text
//vp report split 1-2
```

Reports only the interval between Split 1 and Split 2.

Split 1 と Split 2 の間だけを report します。

Splits combine with categories, enemies and destinations:

Split は category、enemy、destination と組み合わせられます。

```text
//vp report split 1 ranged
//vp report split 1-2 magic
//vp report Papesse split 1-2 ws party
//vp Papesse report pet split 2 alliance
```

For explicit actor scope, use `scope`/`mode`/`actors`/`from`:

Actor scope を明示する場合は `scope` / `mode` / `actors` / `from` を使用します。

```text
//vp report Papesse full scope party to alliance
```

This reports Party actor data to Alliance chat.

これは Party actor data を Alliance chat へ report します。

## Target and Incoming / Target と Incoming

When a current target exists, the target line shows its name, reliable HP information and the currently registered incoming enemy ability or spell.

Current target が存在する場合、target line には name、信頼できる HP information、現在登録されている incoming enemy ability/spell が表示されます。

```text
Target: Aminon | HP: 33% | Incoming: Dancing Fullers
```

If reliable absolute maximum HP is known:

信頼できる absolute maximum HP が判明している場合:

```text
Target: Aminon | HP: 111,111/333,333 (33%) | Incoming: Dancing Fullers
```

Incoming actions remain visible while readying/casting. When the action resolves or is interrupted, the warning flashes twice and clears. Enemy-action detection is based on action/resource data rather than English combat-log text.

Incoming action は readying/casting 中保持されます。Action が resolve または interrupt されると warning は 2 回 flash して消えます。Enemy-action detection は English combat-log text ではなく action/resource data を基準にします。

## HUD appearance / HUD 表示

Background opacity uses a simple 0–100 scale and accepts arbitrary numeric values.

Background opacity は 0–100 の簡単な scale を使用し、任意の数値を指定できます。

```text
//vp bg 0
//vp bg 43
//vp bg 79
//vp bg 100
```

`0` is fully transparent and `100` is fully opaque.

`0` は完全 transparent、`100` は完全 opaque です。

Themes:

```text
//vp theme dark
//vp theme light
//vp inverse
//vp theme highcontrast
//vp hc
```

Light/Inverse remaps warning and status colors for visibility rather than simply inverting RGB values. Custom RGB commands are intentionally not exposed; advanced users may edit configuration values directly.

Light/Inverse は RGB を単純反転せず、warning/status color を visibility に合わせて remap します。Custom RGB command は意図的に公開していません。Advanced user は必要に応じ configuration value を直接編集できます。

## Existing views and analysis / 既存 view と analysis

The full 1.1.0.0 parser architecture remains in this release. Existing combat capture, dynamic/specialized views, filters, actor performance, magic detail, Magic Bursts, ranged attacks, pets, healing, recovery, defense, target filtering, logging, enemy registry and session/split tools remain available unless explicitly changed above.

1.1.0.0 の full parser architecture はこの release に保持されています。既存の combat capture、dynamic/specialized view、filter、actor performance、magic detail、Magic Burst、ranged attack、pet、healing、recovery、defense、target filter、logging、enemy registry、session/split tool は上記で明示的に変更されたものを除き維持されています。

Use `//vp help` in game for the concise command list for the installed build.

Install された build の concise command list は game 内で `//vp help` を使用してください。


## Zone/Teleport Safety / Zone・Teleport 安全処理

VanaParse 1.1.3.0 pauses entity-dependent parsing during full zone changes, instance entry and detected large in-zone teleport/submap transitions. Unsafe first actions are dropped rather than being processed against stale entity state. No cumulative SESSION log is written on every zone transition.

VanaParse 1.1.3.0 は full zone change、instance entry、large in-zone teleport／submap transition の間、entity-dependent parsing を一時停止します。State が不完全な first action は stale entity data に対して処理せず安全に破棄します。Zone transition ごとの cumulative SESSION log は書き込みません。

## Points Row / Points Row

The Points row is optional and passive. VanaParse does not inject currency requests. It uses naturally received packets and keeps the row to one line maximum.

Points row は optional かつ passive です。VanaParse は currency request を inject せず、自然に受信した packet のみを使用し、row は最大 1 行に保ちます。

```text
//vp points on
//vp points off
//vp show points
//vp hide points
```

Relevant examples include Gallimaufry, Mog Segments, Temenos/Apollyon Units, Nyzul Tokens and EP/hour when observed.

表示対象には observed data に応じて Gallimaufry、Mog Segments、Temenos/Apollyon Units、Nyzul Tokens、EP/hour などが含まれます。

## Other-player Job Inference / 他 Player Job 推定

When Windower does not expose another player's job directly, VanaParse can infer a main job conservatively from main-job-exclusive/high-level actions. It never guesses from generic abilities shared with support jobs. Support-job inference requires separate evidence after a different main job is already known.

Windower が他 player の job を直接提供しない場合、VanaParse は main-job-exclusive／high-level action から main job を保守的に推定できます。Support job と共有できる generic ability だけでは推測しません。Support job の推定には、別の main job が既に判明している状態で独立した evidence が必要です。

## Pet Identity / Pet Identity

Pet damage is keyed through the pet actor and master relationship, not the pet display name. `owner_id` is preferred, with `pet_index` fallbacks for cases where owner data is missing. Two different players may therefore use identically named pets without their damage merging together.

Pet damage は pet display name ではなく pet actor と master relationship で識別します。`owner_id` を優先し、owner data がない場合は `pet_index` を fallback として使用するため、別 player が同名 pet を使用しても damage は混在しません。

## All Observed Participants / 観測可能な全参加者

VanaParse 1.1.3.1 adds an encounter-bound `All` actor scope. Once your Party/Alliance has established an encounter, VanaParse can retain outside players and pets that your client observes directly acting on the same known enemy. This is intended for shared bosses and other fights that can exceed 18 contributors.

VanaParse 1.1.3.1 では encounter に限定した `All` actor scope を追加しました。Party/Alliance が encounter を確立した後、同じ既知 enemy に直接 action する outside player／pet を client が観測できる場合、その data を保持できます。18 人を超える shared boss などを想定しています。

```text
//vp mode all
//vp scope all
//vp set scope all
```

`Alliance` remains the default. `All` means all relevant combat contributors observed by the local FFXI client, not every player in the zone. Unrelated nearby fights are not intentionally merged into the encounter. HUD row limits still control how many ranked actors are visible; `//vp set rows all` can show every retained row.

Default は引き続き `Alliance` です。`All` は zone 内の全 player ではなく、local FFXI client が観測した relevant combat contributor を意味します。近くの無関係な fight は encounter に意図的に統合しません。HUD row limit は表示人数のみを制御し、`//vp set rows all` で保持している全 row を表示できます。
