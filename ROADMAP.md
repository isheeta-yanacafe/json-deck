# Roadmap (Ideas / Not committed)

Nothing on this page is a promise. These are directions the project might explore — not a schedule, and not a guarantee that any of it ships. Treat this as "things worth thinking about," not a backlog.

Today, JSON Deck is scoped to editing a single JSON file at a time.

## Known bugs

- [ ] `json-deck.en.html`: the "not set" cell placeholder text (shown on an empty editable cell) is still in Japanese (`未設定（クリックして入力）`) instead of English — a leftover from the original translation pass

## Directions being considered

- ~~Column-based filtering and sorting, alongside the existing full-text search~~
  - Sorting: implemented (any column, ascending/descending, including _added_at)
  - Filtering: not yet implemented (a separate axis from the existing tag filter and full-text search)
- [ ] Optional JSON Schema validation for records
- [ ] Opening a folder and treating several JSON files as related tables
- [ ] A lightweight query syntax for filtering (something in the spirit of JMESPath)
- [ ] Per-column show/hide toggling (e.g. for users who want to hide the tags column)
  - Persistence policy (saved into the file vs. session-only) not yet decided
- [ ] Add a tree-structure view (a third display mode alongside Table/Card)
  - Background: Table/Card requires `normalize()` to force JSON's tree structure into a flat table,
    which misfires on JSON that contains an array but is really a single record — e.g.
    `{ name: "Tanaka", age: 14, clubs: ["Soccer Club", "Computer Club"], isPresident: false }` —
    where what should be one record gets incorrectly expanded into multiple records based on the
    array's contents
  - Idea: add a view that shows the JSON's structure as-is, as a collapsible tree, without converting it
  - UX idea: on paste/file load, detect structures that don't map well to a table (e.g. a top-level
    object whose only array property contains just short strings) and default to tree view
    automatically, with the Table/Card toggle grayed out and a reason shown
    (discovered via a school student-profile JSON example)
  - Open questions: read-only vs. editable; the detection criteria for "doesn't map well to a table" itself
- [ ] Let the user choose the "source of truth" property at load time (an alternative to `normalize()`'s
      automatic guess)
  - Background: `normalize()` mechanically picks the first array property as "the list of records"
    without looking at its contents, which misfires on JSON that contains an array but is really a
    single record (e.g. the school student-profile JSON example from the tree-view item above). No
    amount of smarter heuristics can fully resolve this ambiguity, so letting a human decide only when
    it's actually ambiguous is more reliable
  - Idea: when an array property is found (including when there are multiple), show a dialog asking
    which property to use as the list of records (or to treat the whole object as a single record).
    Default to the current behavior (use the first array found) to preserve backward compatibility
  - "Re-choose" idea: keep a small persistent button (e.g. "🔀 Change which field is used as rows")
    that lets the user re-run the choice against the original parsed data at any time, without
    re-pasting or re-opening the file. Re-choosing discards any in-progress edits, so it should prompt
    the same confirmation as the existing `confirmDiscardIfDirty()`. This is a separate mechanism from
    the regular Undo (Ctrl+Z), consistent with the existing design where Undo covers post-load edits,
    not the load action itself
  - Complements (doesn't compete with) the tree-view item above — this resolves ambiguity before
    loading, tree view is the escape hatch after loading when table form isn't wanted
  - Open questions: UI for when multiple array properties exist; exact dialog wording/UI

## Out of scope

Anything that would require a server — multi-user concurrent editing, real-time sync, and similar — isn't being considered. It would conflict with the tool staying serverless and fully client-side, which is a core part of what it is.

## Feedback

Thoughts and pull requests are welcome. For anything beyond a small fix, please open an issue first so the approach can be discussed — see [CONTRIBUTING.md](./CONTRIBUTING.md).

---

# ロードマップ（アイデア段階・確約ではありません）

このページに書かれているものは、どれも確約ではありません。プロジェクトが検討しうる方向性を並べているだけで、スケジュールでも実装の保証でもありません。「バックログ」ではなく「考える価値のあること」として読んでください。

現状のJSON Deckは、1つのJSONファイルを編集することに機能を絞っています。

## 既知の不具合

- [ ] `json-deck.en.html`: 未設定セルのプレースホルダー文言（空の編集可能セルに表示される案内）が英語版なのに日本語（`未設定（クリックして入力）`）のまま残っている（当初の翻訳作業の取りこぼし）

## 検討中の方向性

- ~~列指定でのフィルタ・ソート機能~~
  - ソート: 実装済み（任意カラム昇順/降順、_added_at含む）
  - フィルタ: 未実装（既存のタグ絞り込み・検索とは別軸での列指定フィルタ）
- [ ] レコードに対するオプショナルなJSON Schemaバリデーション
- [ ] フォルダを開いて、複数のJSONファイルを関連するテーブルとして扱う機能
- [ ] 軽量なクエリ構文によるフィルタリング（JMESPathのような方向性）
- [ ] 任意カラムの表示/非表示切り替え（例: タグ列を隠したいユーザー向け）
  - 状態の永続化方針（ファイル保存 vs セッションのみ）は未検討
- [ ] ツリー構造ビューの追加（テーブル/カードに次ぐ第三の表示モード）
  - 背景: テーブル/カードは`normalize()`がJSONの木構造を無理やり表形式に変換する必要があり、
    「配列を含むが実質は単一レコード」のようなJSON（例:
    `{ 名前: "たなか", 年齢: 14, 部活: ["サッカー部", "パソコン部"], 生徒会長: false }`）では、
    本来1件のレコードであるべきものが、配列の中身の数だけ複数レコードとして誤って展開されてしまう
  - 案: JSONの構造を変換せず、折りたたみ可能な木構造としてそのまま表示するビューを追加する
  - UX案: 貼り付け/ファイル読み込み時に構造を判定し、「表になりにくい」形（例: トップレベル
    オブジェクトの配列プロパティの中身が短い文字列のみ、など）と判定された場合は自動的にツリー
    表示をデフォルトにし、テーブル/カードのトグルはグレーアウトしてその理由を表示する
    （中学校の生徒プロフィールJSONの検証で発見したケースがきっかけ）
  - 未検討事項: 読み取り専用か編集可能か／「表になりにくい」の判定基準そのもの

- [ ] 読み込み時に「主（ぬし）」を人間が選べるようにする（`normalize()`の機械的推測に代わる案）
  - 背景: `normalize()`は、オブジェクトの中の配列プロパティを中身を見ずに機械的に「行の一覧」として
    採用するため、「配列を含むが実質は単一レコード」のJSON（例: 中学校の生徒プロフィールJSON、
    上記ツリー構造ビュー項目の例と同じ）で誤展開が起きる。これはヒューリスティックをどれだけ賢く
    しても原理的に解消しきれない曖昧さのため、判断が必要な場面だけ人間に選ばせる方が構造的に確実
  - 案: 配列プロパティが見つかった時点（複数ある場合も含む）で、「どの項目を行の一覧として使うか
    （／単一レコードとして扱うか）」を選択するダイアログを出す。デフォルト選択は現行動作
    （最初に見つかった配列を採用）とし、後方互換を保つ
  - 「選び直し」案: 一度選んだ後でも「🔀 行として使う項目を変更」のような常設ボタンから、元の
    パース結果に対して選び直しができるようにする（テキストの再貼り付けやファイルの再選択は不要）。
    選び直し時は編集中の内容が失われるため、既存の`confirmDiscardIfDirty()`と同様の確認を挟む。
    通常のUndo（Ctrl+Z）とは別の仕組みとして扱う（Undoは読み込み後のセル編集等が対象で、読み込み
    行為自体は元々Undo対象外という既存の設計方針に合わせるため）
  - 上記「ツリー構造ビュー」の項目とは競合せず補完関係（こちらは読み込み前に曖昧さを解消する案、
    ツリービューは読み込み後に表形式にしたくない場合の逃げ道）
  - 未検討事項: 配列プロパティが複数ある場合のUI（選択肢の並べ方）／ダイアログの具体的な文言・UI

## ネストしたオブジェクトの表示方法の改善（アイデア）

現状、カード内で `dimensions` や `warehouseLocation` のような
「オブジェクトの中にさらにオブジェクトが入っている項目」は、
`{...} 編集` という折りたたみボタンで表示され、クリックするまで
中身が見えない。

これはユーザーが「見るだけ」でも一手間かかってしまい、
「ツールが構造判断を先回りして隠してしまう」という点で、
JSON Deckの基本方針（ユーザー自身がデータを把握・判断できる状態を保つ）
とややズレている。

### 改善案
- 折りたたみボタンではなく、中身をJSON形式のプレーンテキストとして
  常時展開し、コードブロック風の枠（等幅フォント、薄い背景色）の中に
  表示する
- 「見る」はこの表示で完結させ、「編集」は引き続き既存の編集ボタンから行う
  （表示と編集の役割を分ける）
- 中身の構造（配列を含む/含まない等）によらず同じ方式で対応できるため、
  過剰な作り込みをせずに済む

きっかけ：商品データ（productId, tags, dimensions等を含む）を貼り付けた際、
tagsはタグとして正しく表示された一方、dimensions・warehouseLocationは
折りたたまれて中身が見えず、使い勝手の面で改善余地があると判明した。

## 対象外

サーバーを必要とするもの（複数ユーザーでの同時編集、リアルタイム同期など）は検討していません。サーバーレスで、ブラウザ内で完結するという、このツールの根幹をなす性質と矛盾するためです。

## フィードバック

ご意見・Pull Requestを歓迎します。小さな修正以外は、まずIssueで方針を相談してください — 詳しくは [CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。
