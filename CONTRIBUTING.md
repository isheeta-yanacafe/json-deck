# Contributing

Thanks for your interest in improving JSON Deck. This is a small, single-file tool, and the guidelines below are meant to keep it that way.

## Reporting bugs

Please open an issue and include:

- Steps to reproduce
- What you expected to happen, and what actually happened
- The browser (and version) you're using
- If possible, a small sample of the JSON that triggers the problem — especially if the file has an unusual shape (deeply nested, mixed types, non-standard structure)

A minimal reproducible JSON snippet is the single most useful thing you can attach to a bug report.

## Proposing changes

For small fixes (typos, obvious bugs, broken links), a pull request on its own is fine.

For anything that adds a feature or changes existing behavior, please open an issue first to discuss the approach before writing code. This avoids spending effort on a PR that doesn't fit the project's direction.

## Design decisions to be aware of

**Native `alert` / `confirm` / `prompt` are used on purpose.** This project deliberately avoids building a custom modal/dialog UI for these interactions, to keep the tool a single small file with no framework and minimal code to maintain. If you'd like to propose replacing them with custom UI, please raise it in an issue first — this is a considered trade-off, not an oversight.

**`json-deck.html` and `json-deck.en.html` must stay in sync.** The English file is a translation of the Japanese one: identical logic, identical CSS, identical variable names and code comments — only user-facing text (button labels, messages, placeholders, the demo data) differs. Any change to behavior or markup structure must be applied to **both** files. Pull requests that touch one file but not the other will be asked to update the counterpart before merging.

---

# コントリビューションガイド

JSON Deckへの関心をありがとうございます。これは1ファイル完結の小さなツールであり、以下の方針はその性質を保つためのものです。

## バグ報告

Issueを立てる際は、以下を含めてください。

- 再現手順
- 期待していた動作と、実際に起きた動作
- 使用しているブラウザ（バージョン含む）
- 可能であれば、問題を再現する小さなJSONのサンプル — 特に、構造が特殊な場合（深いネスト、型の混在、非標準的な構造など）は重要です

バグ報告に添えられる情報の中で、最小限の再現可能なJSONサンプルが最も役立ちます。

## 変更の提案

タイポや明らかなバグ、リンク切れなどの小さな修正であれば、Pull Requestをそのまま送っていただいて構いません。

機能追加や既存の挙動の変更を伴うものについては、コードを書く前にまずIssueで方針を相談してください。プロジェクトの方向性と合わないPRに労力を使わせてしまうことを避けるためです。

## 知っておいてほしい設計方針

**`alert`/`confirm`/`prompt` はあえてブラウザネイティブのまま使っています。** このプロジェクトは、これらの操作専用にカスタムのモーダルUIを作ることを意図的に避けています。フレームワーク無しの単一の小さなファイルという性質と、保守すべきコード量を最小限に保つためです。これらをカスタムUIに置き換える提案がある場合は、先にIssueで相談してください。見落としではなく、意図した上でのトレードオフです。

**`json-deck.html` と `json-deck.en.html` は同期させる必要があります。** 英語版は日本語版の翻訳であり、ロジック・CSS・変数名・コード内コメントはすべて同一で、画面に表示される文言（ボタンラベル、メッセージ、プレースホルダー、デモデータ）だけが異なります。挙動やマークアップ構造に関わる変更は、**両方のファイル**に反映してください。片方のファイルだけを変更したPull Requestは、マージ前にもう片方への反映をお願いすることになります。
