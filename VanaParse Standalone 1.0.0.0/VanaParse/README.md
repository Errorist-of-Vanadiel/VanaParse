# VanaParse 1.0.0.0

VanaParse is a real-time Final Fantasy XI combat parser for Windower 4. It tracks damage, DPS, accuracy, weapon skills, skillchains, magic, pets, healing and target-specific performance while combat is happening.

VanaParse は Windower 4 用のリアルタイム Final Fantasy XI 戦闘解析アドオンです。戦闘中の Damage、DPS、Accuracy、Weapon Skill、Skillchain、Magic、Pet、Healing、Target ごとの performance を追跡します。

**Author:** Errorist of Vana'diel  
**License:** MIT  
**Standalone version:** 1.0.0.0  
**Embedded VanaCore:** 0.3.3.0

**作者:** Errorist of Vana'diel  
**ライセンス:** MIT  
**Standalone バージョン:** 1.0.0.0  
**内蔵 VanaCore:** 0.3.3.0

## Installation / インストール

Copy the `VanaParse` folder into `Windower4/addons/`, then load it with `//lua load VanaParse`.

`VanaParse` フォルダを `Windower4/addons/` にコピーし、`//lua load VanaParse` で読み込みます。

The package contains only the runtime source, embedded Core, required bundled data, license, version information and this README. Runtime settings, logs and learned enemy data are created locally after use and are not included in the release.

このパッケージには runtime source、内蔵 Core、必要な bundled data、license、version 情報、この README のみを含みます。Settings、logs、learned enemy data は使用後にローカルで生成され、release には含まれません。

## Key commands / 主なコマンド

- `//vp help` — show live command help.  
  `//vp help` — コマンドヘルプを表示します。
- `//vp reset` or `//vp clear` — clear the current full parse/session.  
  `//vp reset` または `//vp clear` — 現在の parse/session 全体をクリアします。
- `//vp compact` — use the compact combat view.  
  `//vp compact` — コンパクト戦闘表示を使用します。
- `//vp split <name>` — begin a named comparison interval.  
  `//vp split <name>` — 名前付き比較区間を開始します。
- `//vp splits` — list saved split intervals.  
  `//vp splits` — 保存済み split 区間を一覧表示します。
- `//vp filter ...` — filter by enemy or damage category without deleting session data.  
  `//vp filter ...` — Session data を削除せず enemy または damage category で絞り込みます。
- `//vp report party` — send the standard paced report to party chat. Other supported destinations include alliance, linkshell, linkshell2, say, yell and tell.  
  `//vp report party` — 標準 report を間隔を空けて Party chat へ送信します。Alliance、Linkshell、Linkshell2、Say、Yell、Tell にも対応します。

Use `//vp help` in game for the authoritative command list for this build.

この build の正式なコマンド一覧はゲーム内で `//vp help` を使用してください。

## Runtime data / 実行時データ

VanaParse may create `VanaParse/data/` for local settings, logs and learned enemy information. These files are intentionally excluded from the clean release and should generally not be committed to a public repository.

VanaParse は local settings、logs、learned enemy information 用に `VanaParse/data/` を作成する場合があります。これらは clean release には含まれず、通常は public repository に commit しないでください。
