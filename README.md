# VanaParse 1.1.0.0

VanaParse is a real-time Final Fantasy XI combat parser for Windower 4. It tracks damage, DPS, accuracy, weapon skills, skillchains, magic, Magic Bursts, ranged attacks, pets, healing, status recovery, defense and target-specific performance while combat is happening.

VanaParse は Windower 4 用のリアルタイム Final Fantasy XI 戦闘解析アドオンです。戦闘中の Damage、DPS、Accuracy、Weapon Skill、Skillchain、Magic、Magic Burst、Ranged Attack、Pet、Healing、Status Recovery、Defense、Target ごとの performance を追跡します。

**Author:** Errorist of Vana'diel  
**License:** MIT  
**Standalone version:** 1.1.0.0  
**Embedded VanaCore:** 0.3.3.0

**作者:** Errorist of Vana'diel  
**ライセンス:** MIT  
**Standalone バージョン:** 1.1.0.0  
**内蔵 VanaCore:** 0.3.3.0

## Installation / インストール

Copy the `VanaParse` folder into `Windower4/addons/`, then load it with `//lua load VanaParse`.

`VanaParse` フォルダを `Windower4/addons/` にコピーし、`//lua load VanaParse` で読み込みます。

This clean release contains only the runtime source, embedded Core, required bundled data, license, version file, `.gitignore` and README. Settings, logs, learned enemy data and character/session data are generated locally and are not included.

この clean release には runtime source、内蔵 Core、必要な bundled data、license、version file、`.gitignore`、README のみを含みます。Settings、logs、learned enemy data、character/session data はローカルで生成され、release には含まれません。

## Simple command model / シンプルなコマンド方式

Commands are action first: **what you want to do**, then **what you want it done to**.

コマンドは action first です。最初に「何をしたいか」、次に「何に対して行うか」を指定します。

- `//vp hide magic` — hide Magic and Magic Burst HUD fields without stopping capture.
- `//vp show magic` — restore Magic and Magic Burst HUD fields.
- `//vp hide mb` — hide only Magic Burst fields.
- `//vp add ranged` / `//vp remove ranged` — add or remove Ranged fields from the HUD.
- `//vp include physical` / `//vp exclude physical` — include or exclude Physical, WS and SC contribution from the active calculation.
- `//vp include trusts` / `//vp exclude trusts` — include or exclude Trust rows without deleting captured session data.
- `//vp filter Aminon` — add an enemy-name filter.
- `//vp unfilter Aminon` — remove that enemy filter.
- `//vp filter Bats` — aggregate enemies whose names contain `Bats`.
- `//vp filter magic` — temporarily calculate the filtered view from Magic damage only.
- `//vp unfilter all` — restore the unfiltered parse.

`hide/show/add/remove` change presentation only. `include/exclude` change the active calculation without deleting captured data. `filter/unfilter` change the active enemy/damage view without deleting the full session.

`hide/show/add/remove` は表示のみを変更します。`include/exclude` は保存済みデータを削除せず active calculation を変更します。`filter/unfilter` は full session を保持したまま active enemy/damage view を変更します。

## Views / 表示モード

- `//vp view dynamic` — default adaptive view, capped at 18 columns.
- `//vp view compact` — compact essentials.
- `//vp view physical`
- `//vp view magic`
- `//vp view ranged`
- `//vp view defense`
- `//vp view combo`
- `//vp view healing`
- `//vp view pet`
- `//vp view ws`

Dynamic includes `Magic Dmg` by default. Compact shows Magic and Pet damage only when their contribution is significant.

Dynamic では `Magic Dmg` を標準表示します。Compact では Magic と Pet の寄与が有意な場合のみ表示します。

## Reporting / レポート

Reporting follows: `//vp report <what> [player] <where>`.

Report は `//vp report <what> [player] <where>` の順で指定します。

Examples:

- `//vp report full party`
- `//vp report dps alliance`
- `//vp report physical party`
- `//vp report magic Errorist party`
- `//vp report mb Errorist party`
- `//vp report ranged linkshell`
- `//vp report healing party`
- `//vp report recovery party`
- `//vp report defense party`
- `//vp report pet party`
- `//vp report pet physical party`
- `//vp report pet magic party`
- `//vp report pet ranged party`
- `//vp report pet healing party`
- `//vp report % party`
- `//vp report performance Errorist party`
- `//vp report performance Errorist all party` — exhaustive nonzero detail.
- `//vp report full tell PlayerName`

Supported destinations: `party`, `alliance`, `linkshell`, `linkshell2`, `say`, `yell`, `tell <name>` and `local`. A normal multi-actor report uses up to 9 actors; add `all` to report every tracked actor. Chat output is queued with a configurable delay so lines are not dumped too quickly.

送信先は `party`、`alliance`、`linkshell`、`linkshell2`、`say`、`yell`、`tell <name>`、`local` に対応します。通常は最大 9 actors を report し、`all` を追加すると全 tracked actors を対象にします。Chat 出力は行落ちを防ぐため delay queue を使用します。

## Player performance / プレイヤー詳細

- `//vp performance Errorist`
- `//vp stat Errorist`
- `//vp performance Errorist all`

The normal performance summary suppresses zero and trivial damage categories. `all` returns all recorded nonzero detail, including WS breakdowns, spell/MB breakdowns, healing, recovery and defensive metrics.

通常の performance summary は 0 またはごく小さい damage category を省略します。`all` は WS breakdown、spell/MB breakdown、healing、recovery、defense を含む記録済み nonzero detail を表示します。

Healing is HP restoration. Healing Waltz and other ailment-removal actions are tracked under Recovery/Status rather than HP Healing.

Healing は HP restoration を意味します。Healing Waltz などの ailment removal は HP Healing ではなく Recovery/Status として追跡します。

## Session tools / Session ツール

- `//vp split Food`
- `//vp split Mighty Strikes`
- `//vp unsplit`
- `//vp reset` or `//vp clear` — full parse/session reset.
- `//vp set rows 8` / `//vp set rows all` / `//vp set rows default`
- `//vp set delay 0.65`
- `//vp show status` / `//vp show filters` / `//vp show splits`
- `//vp help`

Use `//vp help` in game for the authoritative concise command list for this build.

この build の正式な簡潔 command list はゲーム内で `//vp help` を使用してください。
