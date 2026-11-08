# karukan-kz 辞書

Karukan（karukan-kz パッチ入り）のための辞書一式です。2026-11-07 作成。

## 中身

| ファイル | 中身 | 件数 |
|---|---|---|
| `user_dicts/10-bluearchive.txt` | ブルーアーカイブ（生徒は公式ゲームデータで読みを確認） | 696 |
| `user_dicts/11-jujutsukaisen.txt` | 呪術廻戦（人物・術式・用語） | 272 |
| `user_dicts/12-touhou.txt` | 東方Project（キャラ・スペル・曲名・二つ名など） | 13,972 |
| `user_dicts/13-nichijo.txt` | 日常語（システム辞書に無い読みのもの） | 1,633 |
| `user_dicts/20-yojijukugo.txt` | 四字熟語・難しい漢語（浅学非才・韋編三絶など） | 5,553 |
| `system/top.tsv` | 作品の名前・用語のうち、普通の言葉と読みが同じもの | 1,852 |
| `system/additions.tsv.xz` | システム辞書に足す言葉（ニコニコ×ピクシブ、Wikipedia、NEologd、SKK など） | 1,145,210 |

## 並び方のルール

Karukan は「学習 → ユーザー辞書 → AI → システム辞書」の順に候補を並べます。

- `user_dicts/` には、システム辞書が知らない読みの言葉だけを入れています。
  その読みを打つのはその言葉を出したいときなので、1番目に出ても困りません。
- 普通の言葉と読みが同じ名前（ゆうじ → 悠仁、まい → 丁礼田舞 など）は `system/top.tsv` です。
  AI の候補のすぐ後ろに出るので、「ゆうじ」で「有事」を出したいときの邪魔をしません。
- 人の名前は「フルネーム」「姓」「名」「姓 → フルネーム」「名 → フルネーム」で登録しています。
  たとえば「ごじょう」でも「さとる」でも「五条悟」が候補に出ます。

## 使い方

```bash
bash setup.sh             # これだけで全部そろいます
bash setup.sh --update    # Karukan も最新版（パッチ入り）に入れ直す
bash setup.sh --refresh   # 公式のシステム辞書をダウンロードし直す
```

`setup.sh` は次のことを順番にやります。

1. パッチ入りの Karukan（karukan-kz-git）が無ければ `karukan-kz-install.sh` で入れる
2. 公式のシステム辞書をダウンロードし、`system/` の言葉を足して `dict.bin` を作る
   （材料が変わっていなければ作り直さないので、2回目からは数秒で終わります）
3. `~/.local/share/karukan-im/` に `dict.bin` と `user_dicts/*.txt` を登録する
   （あなたの `~/dotfiles/KDE-IME.txt` は `00-KDE-IME.txt` という名前でつなぎます）
4. 登録した辞書が読めるか確かめて、Fcitx5 を再起動する

ユーザー辞書は Mozc と同じ txt のまま登録するので、そのまま書き換えられます。
書き換えたら `bash setup.sh` をもう一度実行するか、Fcitx5 を再起動してください。
`dict.bin` は公式より大きいので、**パッチ入りの Karukan でしか読み込めません**。

## 出典とライセンス

この辞書は、次の自由なライセンスのデータから作っています。
`system/additions.tsv.xz` には GPL と CC BY-SA のデータが含まれるので、
公開のリポジトリに置くときは、このファイル（出典の表示）も一緒に置いてください。

| データ | 作者 | ライセンス |
|---|---|---|
| Karukan 公式システム辞書（ビルド時にダウンロード） | togatoga / SudachiDict | Apache-2.0 |
| mozcdic-ut-sudachidict | utuhiro78 / WorksApplications | Apache-2.0 |
| mozcdic-ut-neologd | utuhiro78 / mecab-ipadic-NEologd | Apache-2.0 |
| mozcdic-ut-jawiki | utuhiro78 / Wikipedia 日本語版 | CC BY-SA |
| mozcdic-ut-edict2 | utuhiro78 / EDRDG | CC BY-SA 4.0 |
| mozcdic-ut-skk-jisyo | utuhiro78 / SKK 辞書 | GPL-2.0-or-later |
| mozcdic-ut-alt-cannadic | utuhiro78 / alt-cannadic | GPL-2.0 |
| mozcdic-ut-personal-names | utuhiro78 | Apache-2.0 |
| mozcdic-ut-place-names | utuhiro78 / 日本郵便 郵便番号データ | パブリックドメイン |
| dic-nico-intersection-pixiv | ncaq（ニコニコ大百科・ピクシブ百科事典） | MIT |
| ブルーアーカイブ生徒名（姓・名・ルビ） | 公式ゲームデータ（electricgoat/ba-data） | 名前の事実データ |
| 作品用語・キャラ名 | あなたの KDE-IME-expanded.txt | あなたのデータ |
