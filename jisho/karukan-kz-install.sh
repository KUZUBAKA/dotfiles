#!/usr/bin/env bash
# karukan-kz-install.sh — Karukan にパッチを当てて入れ直すスクリプト
#
# 使い方:
#   bash karukan-kz-install.sh            最新の Karukan にパッチを当てて入れる（2回目以降はアップデート）
#   bash karukan-kz-install.sh --tested   動作確認済みの版にパッチを当てて入れる
#   bash karukan-kz-install.sh --restore  パッチ無しの AUR 版 karukan-git に戻す
#
# パッチの中身:
#   1. 変換中に文字を打つと、選んでいる候補を確定して次の入力を始める
#      （~/.config/karukan-im/config.toml の [conversion] commit_on_input = false で元に戻せる）
#   2. 入力中に無変換キーを押すと、カタカナ → 半角カタカナ → ひらがな と切り替わる（Mozc・Windows と同じ）
#   3. 読みがぴったり合う辞書の候補を、続きを予測した候補より前に並べる
#      （大きな辞書を入れても、短い読みの変換が予測候補に乗っ取られない）
#   4. ウィンドウごとに辞書を読み直さず、1つの辞書を全ウィンドウで共有する
#      （メモリの節約と、新しいウィンドウで最初の1文字目が固まるのを防ぐ）
#   5. 大きなシステム辞書を読み込めるよう、読み込みの上限を引き上げる
#   6. Space の候補に、AI の文の中の1語だけを辞書の別の書き方に入れかえた候補を足す
#      （何々の旅に → 何々の度に、できていない → 出来ていない）
#   7. 学習した候補のうち、今の読みより長い昔の読み（るる → ルルはその）は AI と辞書の後ろに並べる
#   8. 打った読みとぴったり同じ読みの候補だけを出す（あ → あわせて は出ない）。設定 prediction
#   9. ひらがなで打った読みに英字だけの候補を出さない（かい → KAI は出ない）。設定 alphabet_candidates
#  10. ＠ で始まる読み（＠こいし）は、辞書のキャラクター一覧だけを出す
#  11. 学習した変換を、AI が文脈を見て使うかどうか決める（18 の後ろの さい は 再 ではなく 歳）。
#      ライブ変換でも、文の中の単語にも学習を使う。数字の後ろは助数詞の辞書（〈数〉さい → 歳）を優先。
#      自分で選んでいない変換（ライブ変換のまま Enter）は学習しない。
#  12. AI が「ありそうにない」と見る候補（後ハイ、で着ていない など）を出さない。
#      AI がひらがなのままにした単語（わたしは）も、学習した表記（私は）で出す。
#  13. 学習は「候補から自分で選んだもの」だけを使う（最後に選んだものが先）。昔の版が勝手に
#      覚えた「わたし → わたし」のような行が、選んだ「私」より先に出ることはなくなる。
#  14. 文を単語ごとに辞書と照らして別の表記の文を作り、AI に全部の点数をつけさせて、
#      AI の最初の答えよりはっきり自然なものがあればそれを先頭にする。
#  15. 初期設定を strategy = "main"、chunk_chars = 60 に変更（ベンチマークで正解率が上がったため）。
#  16. 単語の使われやすさ（Mozc の辞書のコスト。辞書セットの setup.sh がシステム辞書に書きこむ）を使う。
#      1語だけの変換でよく使う言葉を先にする（ぼく → 僕、わたし → 私）。助詞・助動詞（から、ます）や
#      こそあど言葉（どこ）は、かなのまま。設定 word_prior
#  17. AI がひらがなのままにした言葉を、かなと同じくらいよく使う漢字で出す（いろんな単語 → 色んな単語）。
#      かなのほうを選べば、その言葉は次からかなのまま。
#  18. 漢字が4〜6字つづく熟語（返還制度）を2つの言葉に分けて、同じ読みのほかの組み合わせ（変換精度）も出す。
#      AI がほとんど差をつけなかったときは、ずっとよく使うほうを先頭にする。
#  19. AI が辞書に無い漢字の組み合わせを作ったとき（螺旋岩）、辞書にある言葉（螺旋丸）を先にする。
#  20. AI が英語で答えたとき（あっぷでーと → Update）は、カタカナ（アップデート）を出す。
#  21. 候補から選ぶと、文ごとではなく単語として覚える（色んな単語 を選ぶと、いろんな人 も 色んな人 になる）。
#  22. アプリが「カーソルの左の文章」を教えてくれないとき（ターミナルなど）、直前に確定した文章を文脈に使う。
#  23. 記号を絵文字より先に出す（はーと → ♡ ♥ ❤）。
#  24. 上の 16〜22 はライブ変換でも同じ。
#  25. 本家の高速化（#153）の上に作り直した。点数づけも同じ方式（KV キャッシュの共有）で速くした。
#  26. 読みを、AI とは別の場所でも単語に区切る（くろきちょう: 黒き蝶 のほかに 黒木町、黒基調、黒貴重）。
#      辞書の単語を並べた「ラティス」から安い区切り方を取り出し、AI に点数をつけさせて候補に入れる。
#      長い文は文節ごと・となり合う2文節ごとに区切り直す（ここではきものをぬぐ → ここで履物を脱ぐ）。
#  27. 学習記録からペルソナを自動で作る（設定 auto_persona）。候補から選んだ言葉を「前に書かれた文章」
#      として AI に見せ、上位の答えを比べ直す（出来る・色んな を選んだ人は たぶん → 多分 になりやすい）。
#  28. kanji_preference とペルソナを、ライブ変換でも使う。
#  29. 点数づけを速くした（文の出だしが同じ候補は、その部分を計算し直さない）。長い文ほど候補を減らす。
#  30. 動詞・形容詞の活用した形（話せ、書い、高かっ）を辞書から引いて、同じ読みのほかの動詞も出す
#      （そのことは話せない → 離せない・放せない、手紙を書いた → 描いた・欠いた）。
#  31. 別の区切り方の候補を選ぶと、その中の単語を覚える（ここで履物を脱ぐ を選ぶと はきもの → 履物）。
set -euo pipefail

readonly KZ_VERSION="bc3247c"
readonly PATCH_SHA256="e02ed76948a09f92b60464c2cdc7279b94f5f22f56f0ac0a9882c75878a50e42"
readonly WORK_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/karukan-kz"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> 注意:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> エラー:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
}

mode=latest
case "${1:-}" in
    "") ;;
    --tested) mode=tested ;;
    --restore) mode=restore ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "知らないオプションです: $1" ;;
esac

(( EUID != 0 )) || die "root（sudo）では実行しないでください。普段のユーザーのまま実行してください。"
for cmd in pacman makepkg git sha256sum b2sum; do
    command -v "$cmd" >/dev/null || die "$cmd が見つかりません。sudo pacman -S --needed base-devel git で入れてください。"
done

if [[ $mode == restore ]]; then
    command -v paru >/dev/null || die "paru が見つかりません。"
    say "パッチ無しの AUR 版 karukan-git に戻します。途中で karukan-kz-git を削除するか聞かれたら y を押してください。"
    paru -S karukan-git
    exit 0
fi

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

say "パッチを書き出しています（$WORK_DIR）"
cat > karukan-kz.patch <<'PATCH_EOF'
From 3543e0f0dc98033ff62c47c22d70de7569999257 Mon Sep 17 00:00:00 2001
From: karukan-patch <noreply@example.invalid>
Date: Sat, 7 Nov 2026 23:12:11 +0900
Subject: [PATCH] =?UTF-8?q?karukan-kz:=20commit=5Fon=5Finput,=20=E7=84=A1?=
 =?UTF-8?q?=E5=A4=89=E6=8F=9B=20kana=20switching,=20shared=20dictionaries,?=
 =?UTF-8?q?=20larger=20dict=20limits,=20word=20swaps,=20exact-only=20and?=
 =?UTF-8?q?=20no-Latin=20options,=20=EF=BC=A0=20character=20lookups,=20lea?=
 =?UTF-8?q?rning=20judged=20in=20context=20(model=20scores),=20counters=20?=
 =?UTF-8?q?after=20numbers,=20chosen-only=20learning,=20per-word=20alterna?=
 =?UTF-8?q?tives=20ranked=20by=20the=20model,=20word=20frequency,=20common?=
 =?UTF-8?q?=20kanji=20spellings,=20compounds,=20a=20word=20lattice,=20a=20?=
 =?UTF-8?q?learned=20persona,=20main=20strategy=20and=2060-char=20chunks?=
 =?UTF-8?q?=20by=20default?=
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

Revision 9, on upstream bc3247c:

- the reading is also cut into words at other places: a lattice of
  dictionary words over the whole reading when short, over each phrase
  and each pair of phrases otherwise; the model judges the cuts with the
  other alternatives (くろきちょう: 黒き蝶, 黒貴重, 黒木町)
- conjugated forms of verbs and adjectives, listed in the system
  dictionary under a mark, give a conjugated word the other verbs of its
  reading (話せない: 離せない, 放せない)
- kana that only reads like a word no longer hides the word that begins
  inside it (それはできない: 出来ない), nor, when it begins with a
  particle, the word behind the particle (相談にのった: 乗った)
- the user's own chosen words (the learning record) judge between the
  model's first answers as a persona (auto_persona)
- a picked cut teaches its words; a cut holding a learned word may lead
- kanji_preference and the persona show in live conversion; words as good
  as always left in kana are not the preference's to convert
- sentences being scored share the tokens they begin with; a long
  sentence gets fewer alternatives

Revision 8: word-frequency prior for bare words, function and こそあど
words left in kana, common kanji spellings and far commoner homophones,
compounds as pairs of words, attested words over made-up compounds,
katakana for English answers, word-level learning, the engine's own
record of committed text as left context, symbols ahead of pictographs.

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QBa6wktjmCU1vbnc5GNtCs
---
 karukan-engine/src/dict.rs                    |    6 +-
 karukan-engine/src/kanji/backend.rs           |   25 +
 karukan-engine/src/kanji/llamacpp.rs          |  135 ++
 karukan-engine/src/learning.rs                |  182 +-
 karukan-im/core/config/default.toml           |   54 +-
 karukan-im/core/src/config/settings.rs        |   66 +-
 karukan-im/core/src/core/candidate.rs         |    5 +
 karukan-im/core/src/core/engine/chunk/mod.rs  |   16 +-
 karukan-im/core/src/core/engine/conversion.rs |  592 +++++-
 karukan-im/core/src/core/engine/display.rs    |   25 +-
 karukan-im/core/src/core/engine/init.rs       |  142 +-
 karukan-im/core/src/core/engine/input.rs      |   10 +-
 karukan-im/core/src/core/engine/lattice.rs    |  380 ++++
 karukan-im/core/src/core/engine/mod.rs        |   37 +-
 karukan-im/core/src/core/engine/mode.rs       |   87 +
 karukan-im/core/src/core/engine/model.rs      |   15 +
 karukan-im/core/src/core/engine/prefer.rs     | 1795 +++++++++++++++++
 karukan-im/core/src/core/engine/swap.rs       |  361 ++++
 .../src/core/engine/tests/candidate_window.rs |    4 +-
 .../src/core/engine/tests/commit_on_input.rs  |  173 ++
 .../core/src/core/engine/tests/conversion.rs  |   16 +-
 .../core/src/core/engine/tests/exact_only.rs  |  194 ++
 .../core/src/core/engine/tests/learning.rs    |   40 +
 karukan-im/core/src/core/engine/tests/mod.rs  |   11 +-
 .../core/src/core/engine/tests/muhenkan.rs    |  128 ++
 .../core/src/core/engine/tests/overload.rs    |    4 +-
 .../core/src/core/engine/tests/predictive.rs  |   44 +-
 .../core/src/core/engine/tests/prefer.rs      | 1391 +++++++++++++
 .../core/src/core/engine/tests/rewriter.rs    |    4 +-
 .../src/core/engine/tests/shared_dicts.rs     |   75 +
 .../src/core/engine/tests/source_filter.rs    |   28 +-
 .../src/core/engine/tests/user_dict_order.rs  |   78 +
 .../core/src/core/engine/tests/width.rs       |    8 +-
 .../core/src/core/engine/tests/word_swap.rs   |   61 +
 karukan-im/core/src/core/engine/types.rs      |   38 +-
 karukan-im/core/src/core/keycode.rs           |    2 +
 36 files changed, 6072 insertions(+), 160 deletions(-)
 create mode 100644 karukan-im/core/src/core/engine/lattice.rs
 create mode 100644 karukan-im/core/src/core/engine/prefer.rs
 create mode 100644 karukan-im/core/src/core/engine/swap.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/commit_on_input.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/exact_only.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/muhenkan.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/prefer.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/shared_dicts.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/user_dict_order.rs
 create mode 100644 karukan-im/core/src/core/engine/tests/word_swap.rs

diff --git a/karukan-engine/src/dict.rs b/karukan-engine/src/dict.rs
index ed6a857..25c2a94 100644
--- a/karukan-engine/src/dict.rs
+++ b/karukan-engine/src/dict.rs
@@ -212,7 +212,9 @@ impl Dictionary {
         // Trie
         r.read_exact(&mut buf4)?;
         let trie_len = u32::from_le_bytes(buf4) as usize;
-        const MAX_TRIE_LEN: usize = 100 * 1024 * 1024; // 100 MB
+        // Sanity caps against a corrupt header, sized for a system dictionary
+        // extended with large vocabularies (Wikipedia, NEologd, ...).
+        const MAX_TRIE_LEN: usize = 1024 * 1024 * 1024; // 1 GiB
         if trie_len > MAX_TRIE_LEN {
             return Err(DictError::Format(format!(
                 "trie_len too large: {} (max {})",
@@ -225,7 +227,7 @@ impl Dictionary {
         // Entries
         r.read_exact(&mut buf4)?;
         let num_entries = u32::from_le_bytes(buf4) as usize;
-        const MAX_ENTRIES: usize = 10_000_000;
+        const MAX_ENTRIES: usize = 50_000_000;
         if num_entries > MAX_ENTRIES {
             return Err(DictError::Format(format!(
                 "num_entries too large: {} (max {})",
diff --git a/karukan-engine/src/kanji/backend.rs b/karukan-engine/src/kanji/backend.rs
index b2c58c5..2c69345 100644
--- a/karukan-engine/src/kanji/backend.rs
+++ b/karukan-engine/src/kanji/backend.rs
@@ -168,6 +168,31 @@ impl KanaKanjiConverter {
         Ok(candidates)
     }
 
+    /// Log-probability of each of `surfaces` as the conversion of `reading`
+    /// after `context` — how plausible the model itself finds a spelling it
+    /// did not necessarily propose. Higher is likelier; comparable between
+    /// surfaces of the same reading and context.
+    pub fn score(&self, reading: &str, context: &str, surfaces: &[&str]) -> Result<Vec<f32>> {
+        let katakana = hiragana_to_katakana(reading);
+        let prompt = build_jinen_prompt(&katakana, context);
+        let prompt_tokens = self.model.tokenize(&prompt)?;
+        let mut continuations = Vec::with_capacity(surfaces.len());
+        for surface in surfaces {
+            // Tokenized together with the prompt, as the model saw it in
+            // training; a tokenizer that merges across the boundary falls
+            // back to the surface alone.
+            let full = self
+                .model
+                .tokenize(&format!("{prompt}{}", normalize_nfkc(surface)))?;
+            continuations.push(match full.strip_prefix(prompt_tokens.as_slice()) {
+                Some(rest) => rest.to_vec(),
+                None => self.model.tokenize(&normalize_nfkc(surface))?,
+            });
+        }
+        self.model
+            .score_continuations(&prompt_tokens, &continuations)
+    }
+
     /// Get a human-readable model name for display
     pub fn model_display_name(&self) -> &str {
         &self.display_name
diff --git a/karukan-engine/src/kanji/llamacpp.rs b/karukan-engine/src/kanji/llamacpp.rs
index 2837ccf..200cd21 100644
--- a/karukan-engine/src/kanji/llamacpp.rs
+++ b/karukan-engine/src/kanji/llamacpp.rs
@@ -1199,6 +1199,141 @@ impl LlamaCppModel {
         Ok(generated)
     }
 
+    /// Log-probability the model gives each of `continuations` (plus the
+    /// end-of-output token) as the text following `prompt`: forced decoding.
+    /// The prompt is evaluated once and its KV cache shared by every
+    /// continuation, and so are the tokens a continuation begins with when
+    /// the first continuation begins with them too: put the sentence the
+    /// others are variations of first. Higher is likelier; values are
+    /// comparable between continuations of one prompt.
+    pub fn score_continuations(
+        &self,
+        prompt: &[LlamaToken],
+        continuations: &[Vec<LlamaToken>],
+    ) -> Result<Vec<f32>> {
+        if prompt.is_empty() || continuations.is_empty() {
+            return Ok(vec![f32::NEG_INFINITY; continuations.len()]);
+        }
+        let n_seq = continuations.len() + 1;
+        let total: usize = continuations.iter().map(Vec::len).sum();
+        // One row per sequence is reserved, and neither decode may be split
+        // (a split batch couples the sequences).
+        let batch_cap = prompt.len().max(total).max(n_seq) + BATCH_HEADROOM;
+        let n_ctx = ((prompt.len() + total + BATCH_HEADROOM) as u32).max(self.n_ctx);
+        // One unified KV buffer (as in the beam search): sharing the prompt
+        // with a continuation then only tags the prompt's cells, where
+        // separate streams would copy the whole K/V buffer every time.
+        let mut ctx = self.new_context(
+            self.context_params_with_n_ctx(n_ctx)
+                .with_kv_unified(true)
+                .with_n_seq_max(n_seq.try_into().unwrap_or(u32::MAX))
+                .with_n_batch(batch_cap as u32)
+                .with_n_ubatch(batch_cap as u32),
+        )?;
+        let vocab_size = self.shared.model.n_vocab() as usize;
+        let eos = self.shared.model.vocab().eos();
+        let log_prob = |logits: &[f32], target: LlamaToken| -> f32 {
+            let logits = &logits[..vocab_size.min(logits.len())];
+            let Some(&t) = logits.get(target.0 as usize) else {
+                return f32::NEG_INFINITY;
+            };
+            let max = logits.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
+            let lse = logits.iter().map(|&x| (x - max).exp()).sum::<f32>().ln() + max;
+            t - lse
+        };
+
+        // The prompt, once, in sequence 0: its last position predicts every
+        // continuation's first token.
+        let mut batch = LlamaBatch::new(batch_cap, 1);
+        self.add_input_tokens(&mut batch, prompt)?;
+        ctx.decode(&mut batch).map_err(inference_err)?;
+        let mut scores: Vec<f32> = {
+            let logits = ctx.get_logits_ith(prompt.len() as i32 - 1);
+            continuations
+                .iter()
+                .map(|c| log_prob(logits, c.first().copied().unwrap_or(eos)))
+                .collect()
+        };
+        if total == 0 {
+            return Ok(scores);
+        }
+
+        // The first continuation — the sentence the others are variations
+        // of — in sequence 1 on top of the shared prompt.
+        let reference = &continuations[0];
+        batch.clear();
+        if !reference.is_empty() {
+            ctx.copy_kv_cache_seq(0, 1, None, None)
+                .map_err(inference_err)?;
+            for (j, &token) in reference.iter().enumerate() {
+                batch
+                    .add(token, (prompt.len() + j) as i32, &[1], true)
+                    .map_err(inference_err)?;
+            }
+            ctx.decode(&mut batch).map_err(inference_err)?;
+        }
+        // What the reference's row `j` says about a token following its
+        // first `j + 1` tokens.
+        let mut shared_prefix: Vec<f32> = Vec::with_capacity(reference.len());
+        for (j, _) in reference.iter().enumerate() {
+            let target = reference.get(j + 1).copied().unwrap_or(eos);
+            let step = log_prob(ctx.get_logits_ith(j as i32), target);
+            scores[0] += step;
+            shared_prefix.push(step);
+        }
+
+        // Every other continuation starts like the reference for a while
+        // (one word of a sentence respelled): those tokens are not decoded
+        // again. Their cells are shared with the reference's sequence, their
+        // log-probabilities are the reference's, and the reference's row
+        // before the first different token predicts that token.
+        let mut tails: Vec<(usize, usize)> = Vec::new();
+        for (k, continuation) in continuations.iter().enumerate().skip(1) {
+            let same = continuation
+                .iter()
+                .zip(reference)
+                .take_while(|(a, b)| a == b)
+                .count();
+            if same > 0 {
+                // Predictions of tokens 1..same, then of the token at `same`
+                // (the end of output when there is none).
+                scores[k] += shared_prefix[..same - 1].iter().sum::<f32>();
+                let next = continuation.get(same).copied().unwrap_or(eos);
+                scores[k] += log_prob(ctx.get_logits_ith(same as i32 - 1), next);
+            }
+            if same < continuation.len() {
+                tails.push((k, same));
+            }
+        }
+        if tails.is_empty() {
+            return Ok(scores);
+        }
+        batch.clear();
+        let mut rows: Vec<(usize, LlamaToken)> = Vec::new();
+        for &(k, same) in &tails {
+            let continuation = &continuations[k];
+            let seq = (k + 1) as i32;
+            ctx.copy_kv_cache_seq(0, seq, None, None)
+                .map_err(inference_err)?;
+            if same > 0 {
+                let from = prompt.len() as u32;
+                ctx.copy_kv_cache_seq(1, seq, Some(from), Some(from + same as u32))
+                    .map_err(inference_err)?;
+            }
+            for (j, &token) in continuation.iter().enumerate().skip(same) {
+                batch
+                    .add(token, (prompt.len() + j) as i32, &[seq], true)
+                    .map_err(inference_err)?;
+                rows.push((k, continuation.get(j + 1).copied().unwrap_or(eos)));
+            }
+        }
+        ctx.decode(&mut batch).map_err(inference_err)?;
+        for (row, (k, target)) in rows.into_iter().enumerate() {
+            scores[k] += log_prob(ctx.get_logits_ith(row as i32), target);
+        }
+        Ok(scores)
+    }
+
     /// Get the EOS token ID from the model
     pub fn eos_token_id(&self) -> LlamaToken {
         self.shared.model.vocab().eos()
diff --git a/karukan-engine/src/learning.rs b/karukan-engine/src/learning.rs
index d65be71..77aea6f 100644
--- a/karukan-engine/src/learning.rs
+++ b/karukan-engine/src/learning.rs
@@ -18,8 +18,15 @@ pub struct LearningEntry {
     pub frequency: u32,
     /// Last selection time as Unix timestamp (seconds)
     pub last_access: u64,
+    /// Whether the user picked this surface from the candidates
+    /// ([`LearningCache::record_chosen`]), as opposed to an entry written
+    /// by a commit nobody chose (older files hold many: わたし → わたし).
+    pub chosen: bool,
 }
 
+/// Fifth column of a row whose surface the user picked.
+const CHOSEN_MARK: &str = "chosen";
+
 /// Size limits for a [`LearningCache`].
 ///
 /// Passed whole at construction ([`LearningCache::new`] /
@@ -62,6 +69,8 @@ pub struct LearningCache {
     max_entries: usize,
     max_surface_chars: usize,
     dirty: bool,
+    /// Counts every change, so a reader can tell when to look again.
+    revision: u64,
 }
 
 impl LearningCache {
@@ -72,6 +81,7 @@ impl LearningCache {
             max_entries: config.max_entries,
             max_surface_chars: config.max_surface_chars,
             dirty: false,
+            revision: 0,
         }
     }
 
@@ -94,9 +104,103 @@ impl LearningCache {
                 surface: surface.to_string(),
                 frequency: 1,
                 last_access: now,
+                chosen: false,
             });
         }
         self.dirty = true;
+        self.revision += 1;
+    }
+
+    /// Record a surface the user picked from the candidates. It is marked
+    /// as chosen, which is what [`preferred`](Self::preferred) goes by.
+    pub fn record_chosen(&mut self, reading: &str, surface: &str) {
+        self.record(reading, surface);
+        if let Some(entry) = self
+            .entries
+            .get_mut(reading)
+            .and_then(|entries| entries.iter_mut().find(|e| e.surface == surface))
+        {
+            entry.chosen = true;
+        }
+    }
+
+    /// What the user prefers for exactly `reading`, best first: the
+    /// surfaces they picked themselves, the latest pick leading (the last
+    /// choice wins, however often another was used before), then entries
+    /// of unknown origin by score. Of those, one that merely repeats the
+    /// reading is left out: it is what a commit of unconverted kana wrote,
+    /// and it would keep the kana ahead of every real choice.
+    pub fn preferred(&self, reading: &str) -> Vec<(String, f64)> {
+        let now = now_unix();
+        let Some(entries) = self.entries.get(reading) else {
+            return Vec::new();
+        };
+        let mut chosen: Vec<&LearningEntry> = entries.iter().filter(|e| e.chosen).collect();
+        chosen.sort_by_key(|e| std::cmp::Reverse(e.last_access));
+        let mut others: Vec<&LearningEntry> = entries
+            .iter()
+            .filter(|e| !e.chosen && e.surface != reading)
+            .collect();
+        others.sort_by(|a, b| score(b, now).total_cmp(&score(a, now)));
+        chosen
+            .into_iter()
+            .chain(others)
+            .map(|e| (e.surface.clone(), score(e, now)))
+            .collect()
+    }
+
+    /// A number that changes whenever the cache does.
+    pub fn revision(&self) -> u64 {
+        self.revision
+    }
+
+    /// Words that tell what and how the user writes, for a persona: of the
+    /// surfaces they picked themselves that are written with kanji or
+    /// katakana, the most used and the latest in turns, as many as fit in
+    /// `budget` characters (a space between two counted), oldest first.
+    /// Entries under a marked reading (`〈数〉さい`) are counters and say
+    /// nothing; long surfaces are sentences, not words.
+    pub fn persona_words(&self, budget: usize) -> Vec<String> {
+        const MAX_WORD_CHARS: usize = 6;
+        let telling = |c: char| matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}' | '\u{30A1}'..='\u{30FA}');
+        let mut words: Vec<&LearningEntry> = self
+            .entries
+            .iter()
+            .filter(|(reading, _)| !reading.starts_with('〈') && !reading.starts_with('＠'))
+            .flat_map(|(_, entries)| entries)
+            .filter(|e| {
+                e.chosen
+                    && e.surface.chars().count() <= MAX_WORD_CHARS
+                    && e.surface.chars().any(telling)
+                    && !e.surface.chars().any(char::is_whitespace)
+            })
+            .collect();
+        // Ties broken by the surface, so the result does not depend on the
+        // order of a hash map.
+        words.sort_by(|a, b| (b.last_access, &b.surface).cmp(&(a.last_access, &a.surface)));
+        let latest = words.clone();
+        words.sort_by(|a, b| {
+            (b.frequency, b.last_access, &b.surface).cmp(&(a.frequency, a.last_access, &a.surface))
+        });
+        let mut picked: Vec<&LearningEntry> = Vec::new();
+        let mut used = 0;
+        for entry in words
+            .iter()
+            .zip(&latest)
+            .flat_map(|(most_used, newest)| [*most_used, *newest])
+        {
+            if picked.iter().any(|p| p.surface == entry.surface) {
+                continue;
+            }
+            let cost = entry.surface.chars().count() + usize::from(!picked.is_empty());
+            if used + cost > budget {
+                continue;
+            }
+            used += cost;
+            picked.push(entry);
+        }
+        picked.sort_by(|a, b| (a.last_access, &a.surface).cmp(&(b.last_access, &b.surface)));
+        picked.into_iter().map(|e| e.surface.clone()).collect()
     }
 
     /// Remove every learned entry that would resurface `surface` for input
@@ -118,6 +222,7 @@ impl LearningCache {
         });
         if removed {
             self.dirty = true;
+            self.revision += 1;
         }
         removed
     }
@@ -208,6 +313,8 @@ impl LearningCache {
                     surface: surface.to_string(),
                     frequency,
                     last_access,
+                    // A fifth column marks a surface the user picked.
+                    chosen: parts.get(4) == Some(&CHOSEN_MARK),
                 });
         }
 
@@ -235,11 +342,15 @@ impl LearningCache {
         for reading in readings {
             if let Some(entries) = self.entries.get(reading) {
                 for entry in entries {
-                    writeln!(
+                    write!(
                         writer,
                         "{}\t{}\t{}\t{}",
                         reading, entry.surface, entry.frequency, entry.last_access
                     )?;
+                    if entry.chosen {
+                        write!(writer, "\t{CHOSEN_MARK}")?;
+                    }
+                    writeln!(writer)?;
                 }
             }
         }
@@ -465,11 +576,13 @@ mod tests {
             surface: "A".to_string(),
             frequency: 1,
             last_access: now,
+            chosen: false,
         };
         let old = LearningEntry {
             surface: "B".to_string(),
             frequency: 1,
             last_access: now.saturating_sub(30 * 86400), // 30 days ago
+            chosen: false,
         };
         assert!(score(&recent, now) > score(&old, now));
     }
@@ -481,11 +594,13 @@ mod tests {
             surface: "A".to_string(),
             frequency: 100,
             last_access: now,
+            chosen: false,
         };
         let low_freq = LearningEntry {
             surface: "B".to_string(),
             frequency: 1,
             last_access: now,
+            chosen: false,
         };
         assert!(score(&high_freq, now) > score(&low_freq, now));
     }
@@ -633,3 +748,68 @@ mod tests {
         assert_eq!(cache.entry_count(), 1);
     }
 }
+
+#[cfg(test)]
+mod chosen_tests {
+    use super::*;
+
+    #[test]
+    fn the_latest_pick_leads_and_bare_kana_of_unknown_origin_is_left_out() {
+        let mut cache = LearningCache::new(Default::default());
+        for _ in 0..20 {
+            cache.record("わたし", "わたし");
+        }
+        cache.record("わたし", "渡し");
+        assert_eq!(cache.preferred("わたし")[0].0, "渡し");
+        cache.record_chosen("わたし", "私");
+        let names: Vec<String> = cache.preferred("わたし").into_iter().map(|p| p.0).collect();
+        assert_eq!(names, ["私", "渡し"]);
+        // Kana picked on purpose counts.
+        cache.entries.get_mut("わたし").unwrap()[2].last_access -= 10;
+        cache.record_chosen("わたし", "わたし");
+        assert_eq!(cache.preferred("わたし")[0].0, "わたし");
+    }
+
+    #[test]
+    fn the_mark_survives_save_and_load_and_old_rows_load_unmarked() {
+        let dir = tempfile::tempdir().unwrap();
+        let path = dir.path().join("learning.tsv");
+        let mut cache = LearningCache::new(Default::default());
+        cache.record("さい", "再");
+        cache.record_chosen("さい", "歳");
+        cache.save(&path).unwrap();
+        let text = std::fs::read_to_string(&path).unwrap();
+        assert!(
+            text.contains("歳\t1\t") && text.contains("\tchosen\n"),
+            "{text}"
+        );
+        assert!(
+            text.lines()
+                .any(|l| l.starts_with("さい\t再\t") && l.split('\t').count() == 4)
+        );
+        let loaded = LearningCache::load(&path, Default::default()).unwrap();
+        let names: Vec<String> = loaded.preferred("さい").into_iter().map(|p| p.0).collect();
+        assert_eq!(names, ["歳", "再"]);
+    }
+
+    #[test]
+    fn persona_words_are_the_users_own_kanji_and_katakana_words() {
+        let mut cache = LearningCache::new(LearningConfig::default());
+        cache.record_chosen("でき", "出来");
+        cache.record_chosen("しろこ", "シロコ");
+        // Not chosen, kana only, a counter, a sentence: none of these tell.
+        cache.record("きょう", "今日");
+        cache.record_chosen("いろんな", "いろんな");
+        cache.record_chosen("〈数〉さい", "歳");
+        cache.record_chosen("きょうはいいてんきですね", "今日はいい天気ですね");
+        assert_eq!(cache.persona_words(30), ["シロコ", "出来"]);
+        // As many as fit, a space between two counted.
+        assert_eq!(cache.persona_words(5), ["出来"]);
+        assert!(cache.persona_words(1).is_empty());
+        // The revision tells a reader when to look again.
+        let before = cache.revision();
+        cache.record_chosen("わたし", "私");
+        assert!(cache.revision() > before);
+        assert_eq!(cache.persona_words(30), ["シロコ", "出来", "私"]);
+    }
+}
diff --git a/karukan-im/core/config/default.toml b/karukan-im/core/config/default.toml
index a87bbf0..05d0f73 100644
--- a/karukan-im/core/config/default.toml
+++ b/karukan-im/core/config/default.toml
@@ -3,7 +3,12 @@
 
 [conversion]
 # 変換ストラテジー: adaptive（動的切替）, light（軽量モデルのみ）, main（メインモデルのみ）
-strategy = "adaptive"
+# karukan-kz: main。AJIMEE-Bench（文脈つきの変換 200 問）の先頭 60 問をライブ変換で打って測ると、
+#   adaptive + chunk_chars 30 … 正解 69.5%（遅い PC では軽量モデルに切り替わるため）
+#   main     + chunk_chars 30 … 正解 78.0%
+#   main     + chunk_chars 60 … 正解 86.4%
+# 打つのが重く感じる PC では adaptive に戻す。
+strategy = "main"
 # 変換候補数（Space押下時）
 num_candidates = 9
 # 周辺テキスト（カーソル左側の確定済みテキスト）を変換時のコンテキストとして使用する
@@ -16,7 +21,9 @@ context_chars = 10
 persona = ""
 # 一度にAI変換する Chunk の最大文字数。長文を入力しても1キーあたりの変換時間が
 # 伸びないようにするための区切り。詳細は docs/chunking.md を参照。
-chunk_chars = 30
+# karukan-kz: 60。30 だと 30 文字ごとの区切りが単語の途中に来て、そこが壊れる
+# （過剰摂取した → 過剰摂氏ゅした）。長くするほど 1 キーあたりの変換は重くなる。
+chunk_chars = 60
 # ひと続きで変換する Chunk に残せる記号（、。！？など）の数。
 # この数までの記号は区切らずに一緒に変換されるため、「おい、お前だよ」が
 # 読点を入力した時点で「老、」に固定されず、最後までまとめて変換される。
@@ -36,7 +43,7 @@ chunk_alphabets = 0
 # 別候補（ビームサーチ）を出す範囲の文字数。Chunk の切れ目に合わせて末尾から
 # まとめるため、実際の範囲はこの値以下、かつ最後の Chunk 以上になる。
 # 数字・記号の Chunk と、自分で入れた区切りが境界になる。
-beam_chars = 30
+beam_chars = 60
 # 別候補の本数（ビーム幅）
 beam_width = 3
 # メインモデルの推論がこの時間(ms)を超えたらlight_modelに自動切替(0で無効)
@@ -57,6 +64,47 @@ light_model = "jinen-v2-xsmall-q8"
 n_threads = 4
 # 起動時にライブ変換を有効にする（Ctrl+Shift+L で実行中も切替可能）
 live_conversion = true
+# 変換中（Space で候補を選んでいる間）に文字キーを押したときの動き。
+#   true : 選択中の候補を確定し、押した文字から次の入力を始める（MS-IME / Mozc と同じ）
+#   false: 確定せずに読みを伸ばして変換し直す（Karukan 本来の動き）
+# Ctrl+T / Ctrl+R / Ctrl+I で候補を絞り込んでいる間と絵文字入力中は、検索なので
+# どちらの設定でも読みを伸ばす。
+commit_on_input = true
+# 打った読みより長い読みの候補（続きの予測）を出すか。
+#   false: 読みがぴったり同じ候補だけを出す（あ → あわせて のような候補は出ない）
+#   true : 辞書と学習から、打った読みで始まる長い読みの候補も出す（Karukan 本来の動き）
+prediction = false
+# ひらがな・カタカナで打った読みに、英字だけの辞書の候補（かい → KAI）を出すか。
+# false で出さない。英字で打ったとき（ローマ字のまま Space など）は関係なく出る。
+alphabet_candidates = false
+# 漢字で書く言葉を優先する強さ。AI が一番と見る変換より、漢字の多い変換（辞書にある書き方）が
+# この数字（AI の確からしさの点数の差）以内なら、漢字の多い方を先頭にする。
+#   できていない → 出来ていない、たぶん → 多分
+# 0 で無効。大きくするほど漢字が増える（よろしく → 宜しく、たくさん → 沢山 なども起きやすくなる）。
+# ライブ変換でも同じように働く。
+# ただし、かなのほうがずっとよく使われる言葉（ありがとう と 有難う、ございます と 御座います、
+# そうする と 奏する）と、こそあど言葉（これ、どこ）は、この設定でも漢字にしない。
+# 0 のままでも、かなと同じくらいよく使う漢字（いろんな → 色んな、わたし → 私）は word_prior の働きで
+# 漢字になる。それ以外は、候補から一度選べばその言葉を覚える。
+kanji_preference = 0.0
+# 1つの単語だけを変換するとき、AI の点数に「その言葉がどれくらいよく使われるか」（システム辞書の
+# コスト。Mozc の辞書の数字）を足す重み。AI だけだと単語1つの変換が不安定なため
+# （ぼく → 朴、きかん → 季刊）。左に文があるときは AI に任せるので使わない。
+# 同じデータで、次のこともする（どれも AI の点数が大きく離れていないときだけ）:
+#   - AI がひらがなのままにした言葉を、かなと同じくらいよく使う漢字にする（いろんな単語 → 色んな単語）
+#   - 同じ読みの言葉のうち、ずっとよく使うほうを先頭にする（返還制度が悪い → 変換精度が悪い）
+# 0 で全部無効。辞書セット（setup.sh）で作ったシステム辞書が必要。
+word_prior = 0.3
+
+# 学習記録からペルソナ（あなたが何について・どんな書き方で書く人か）を自動で作る。
+# 候補から選んで覚えた言葉のうち、漢字かカタカナを含む6文字以内のものを、よく使う順と新しい順に
+# 合わせて30文字ぶん集める。変換のたびに、AI が出した上位の答えを「この言葉たちが前に書かれていたら
+# どれが自然か」でもう一度比べ、はっきり変わったものがあれば先頭にする。
+#   出来る・色んな を選んだことがある → たぶん大丈夫 が 多分大丈夫 に
+#   銀行・残高 を選んだことがある     → こうざ が 口座 に
+# AI の文そのものは書きかえない（関係ない言葉まで引っぱられないように、比べるのは AI が自分で出した
+# 答えどうしだけ）。カーソルの左に文章があるときは、その文章のほうが確かなので使わない。false で無効。
+auto_persona = true
 # ユーザー辞書: ~/.local/share/karukan-im/user_dicts/ に辞書ファイルを配置（Mozc TSV or KRKN binary）
 
 # 変換モデル。model / light_model はここのキーを参照する。値は 2 通り:
diff --git a/karukan-im/core/src/config/settings.rs b/karukan-im/core/src/config/settings.rs
index 7dd6a0c..e1fc274 100644
--- a/karukan-im/core/src/config/settings.rs
+++ b/karukan-im/core/src/config/settings.rs
@@ -212,6 +212,29 @@ pub struct ConversionSettings {
     pub n_threads: u32,
     /// Enable live conversion at startup (Ctrl+Shift+L still toggles at runtime)
     pub live_conversion: bool,
+    /// A printable keystroke during an unfiltered conversion commits the
+    /// selection and starts the next composition with it (MS-IME / mozc
+    /// style). `false` keeps the refine-in-place behaviour. Narrowed source
+    /// views and the emoji picker always refine.
+    pub commit_on_input: bool,
+    /// Offer candidates whose reading extends the typed one (predictive
+    /// dictionary and learning completions). `false` keeps only exact
+    /// readings.
+    pub prediction: bool,
+    /// Offer Latin-only dictionary surfaces (かい → KAI) for a reading
+    /// typed in kana.
+    pub alphabet_candidates: bool,
+    /// How far (in nats of the model's log-probability) a conversion that
+    /// writes more of its words in kanji may fall behind the model's best
+    /// one and still lead: いろんな単語 → 色んな単語. 0 turns it off.
+    pub kanji_preference: f32,
+    /// Weight of word frequency (the system dictionary's cost, Mozc's)
+    /// next to the model's score when a reading is one dictionary word.
+    /// 0 turns it off.
+    pub word_prior: f32,
+    /// Whether the words the user chose before (the learning record) are
+    /// put in front of the left context as a persona of their own.
+    pub auto_persona: bool,
 }
 
 /// Learning cache settings
@@ -487,7 +510,7 @@ beam_width = 5
         .unwrap();
 
         let settings = Settings::load_from(file.path()).unwrap();
-        assert_eq!(settings.conversion.chunk_chars, 30);
+        assert_eq!(settings.conversion.chunk_chars, 60);
         assert_eq!(settings.conversion.beam_width, 5);
     }
 
@@ -588,6 +611,45 @@ use_context = false
         assert!(!settings.conversion.use_context);
     }
 
+    #[test]
+    fn test_commit_on_input_default_and_override() {
+        // Shipped default: typing during a conversion commits it.
+        assert!(Settings::default().conversion.commit_on_input);
+
+        let mut file = NamedTempFile::new().unwrap();
+        writeln!(
+            file,
+            r#"
+[conversion]
+commit_on_input = false
+"#
+        )
+        .unwrap();
+        let settings = Settings::load_from(file.path()).unwrap();
+        assert!(!settings.conversion.commit_on_input);
+        assert!(!crate::core::engine::EngineConfig::from_settings(&settings).commit_on_input);
+    }
+
+    #[test]
+    fn test_exact_only_defaults_and_override() {
+        // Shipped default: no completions of longer readings, no Latin-only
+        // dictionary surfaces for kana.
+        let d = Settings::default();
+        assert!(!d.conversion.prediction);
+        assert!(!d.conversion.alphabet_candidates);
+        let c = crate::core::engine::EngineConfig::from_settings(&d);
+        assert!(!c.prediction && !c.alphabet_candidates);
+
+        let mut file = NamedTempFile::new().unwrap();
+        writeln!(
+            file,
+            "[conversion]\nprediction = true\nalphabet_candidates = true"
+        )
+        .unwrap();
+        let s = Settings::load_from(file.path()).unwrap();
+        assert!(s.conversion.prediction && s.conversion.alphabet_candidates);
+    }
+
     #[test]
     fn test_user_dict_dir() {
         let dir = Settings::user_dict_dir();
@@ -735,7 +797,7 @@ num_candidates = 5
 
         let path = file.path().to_path_buf();
         let settings = Settings::load_from(&path).unwrap();
-        assert_eq!(settings.conversion.strategy, StrategyMode::Adaptive);
+        assert_eq!(settings.conversion.strategy, StrategyMode::Main);
     }
 
     #[test]
diff --git a/karukan-im/core/src/core/candidate.rs b/karukan-im/core/src/core/candidate.rs
index a4e7f0b..dc2266a 100644
--- a/karukan-im/core/src/core/candidate.rs
+++ b/karukan-im/core/src/core/candidate.rs
@@ -289,6 +289,11 @@ impl CandidateList {
         }
     }
 
+    /// Append a candidate at the end of the list.
+    pub fn push(&mut self, candidate: Candidate) {
+        self.candidates.push(candidate);
+    }
+
     /// Move the cursor to `cursor`, clamped into the list (0 when empty).
     pub fn set_cursor(&mut self, cursor: usize) {
         self.cursor = cursor.min(self.candidates.len().saturating_sub(1));
diff --git a/karukan-im/core/src/core/engine/chunk/mod.rs b/karukan-im/core/src/core/engine/chunk/mod.rs
index 04945af..d5562d1 100644
--- a/karukan-im/core/src/core/engine/chunk/mod.rs
+++ b/karukan-im/core/src/core/engine/chunk/mod.rs
@@ -127,7 +127,21 @@ impl InputMethodEngine {
     ) -> ComposingChunk {
         let converted = if reading.chars().any(is_japanese) {
             let lctx = self.lctx_for(base_ctx, combined);
-            self.convert_chunk(&reading, &lctx)
+            let converted = self.convert_chunk(&reading, &lctx);
+            // What was learned, where the context allows it: the whole
+            // chunk, or a word inside it (see `prefer`).
+            let converted = self.apply_preferences(&reading, &lctx, converted);
+            // `alphabet_candidates = false`: kana typed as るる must not
+            // turn into lulu on screen, nor あっぷでーと into Update: the
+            // katakana, a dictionary word or the kana as typed instead.
+            if !self.config.alphabet_candidates
+                && super::conversion::is_unwanted_latin(&reading, &converted)
+                && !super::conversion::is_latin_only(&reading)
+            {
+                self.japanese_instead(&reading, &lctx)
+            } else {
+                converted
+            }
         } else {
             reading.clone()
         };
diff --git a/karukan-im/core/src/core/engine/conversion.rs b/karukan-im/core/src/core/engine/conversion.rs
index c694793..12c6320 100644
--- a/karukan-im/core/src/core/engine/conversion.rs
+++ b/karukan-im/core/src/core/engine/conversion.rs
@@ -2,7 +2,7 @@
 //! handling, and commit. Model dispatch lives in the sibling `model`
 //! module, the Ctrl+R source views in `filter`, live chunking in `chunk`.
 
-use std::collections::HashSet;
+use std::collections::{HashMap, HashSet};
 
 use tracing::debug;
 
@@ -48,6 +48,103 @@ enum TailConstraint {
     Dead,
 }
 
+/// Where the first symbols of a reading sit in the list, and how many.
+const SYMBOL_SLOT: usize = 4;
+const SYMBOLS_LIFTED: usize = 4;
+
+/// ほし is typed for ☆ as often as for 星: the first plain symbols the
+/// symbol table has for the reading move up to the fifth to eighth place
+/// instead of trailing every dictionary word (Mozc places them likewise).
+fn lift_symbols(list: &mut Vec<AnnotatedCandidate>) {
+    let is_symbol = |c: &AnnotatedCandidate| {
+        c.source == CandidateSource::Rewriter
+            && !c.text.is_empty()
+            && c.text
+                .chars()
+                .all(|ch| !ch.is_alphanumeric() && (ch as u32) < 0x1_0000)
+    };
+    let found: Vec<usize> = list
+        .iter()
+        .enumerate()
+        .filter(|(_, c)| is_symbol(c))
+        .map(|(i, _)| i)
+        .take(SYMBOLS_LIFTED)
+        .collect();
+    for (n, from) in found.into_iter().enumerate() {
+        let to = SYMBOL_SLOT + n;
+        if from > to {
+            let symbol = list.remove(from);
+            list.insert(to, symbol);
+        }
+    }
+}
+
+/// Whether `reading` is a ＠ character lookup (＠こいし): the user
+/// dictionaries list a character's names and skills under ＠ + name.
+pub(super) fn is_character_query(reading: &str) -> bool {
+    reading.starts_with(['＠', '@']) && reading.chars().count() > 1
+}
+
+/// Whether `reading` holds any hiragana or katakana (full or half width).
+pub(super) fn has_kana(reading: &str) -> bool {
+    reading.chars().any(|c| {
+        ('\u{3041}'..='\u{309F}').contains(&c)
+            || ('\u{30A0}'..='\u{30FF}').contains(&c)
+            || ('\u{FF66}'..='\u{FF9F}').contains(&c)
+    })
+}
+
+/// Whether `text` is written in Latin letters only — ASCII or full-width
+/// letters, digits, spaces and punctuation, with at least one letter
+/// (KAI, Lulu, LuLu!!, ｒｕｒｕ). Greek, kana and kanji are not.
+pub(super) fn is_latin_only(text: &str) -> bool {
+    let mut letter = false;
+    for c in text.chars() {
+        let half = if ('\u{FF01}'..='\u{FF5E}').contains(&c) {
+            char::from_u32(c as u32 - 0xFEE0).unwrap_or(c)
+        } else if c == '\u{3000}' {
+            ' '
+        } else {
+            c
+        };
+        if !half.is_ascii() || half.is_ascii_control() {
+            return false;
+        }
+        letter |= half.is_ascii_alphabetic();
+    }
+    letter
+}
+
+/// Whether `text` holds a piece of romaji: three or more lowercase Latin
+/// letters in a row with no capital or digit beside them (mimiが好きです,
+/// macoら). Tシャツ, USBメモリ and iPhone do not count.
+pub(super) fn has_romaji_fragment(text: &str) -> bool {
+    let chars: Vec<char> = text.chars().collect();
+    let mut i = 0;
+    while i < chars.len() {
+        if !chars[i].is_ascii_alphanumeric() {
+            i += 1;
+            continue;
+        }
+        let start = i;
+        while i < chars.len() && chars[i].is_ascii_alphanumeric() {
+            i += 1;
+        }
+        let run = &chars[start..i];
+        if run.len() >= 3 && run.iter().all(|c| c.is_ascii_lowercase()) {
+            return true;
+        }
+    }
+    false
+}
+
+/// What `alphabet_candidates = false` keeps out of a kana reading's model
+/// answers: English-only text and romaji fragments.
+pub(super) fn is_unwanted_latin(reading: &str, text: &str) -> bool {
+    is_latin_only(text)
+        || (!reading.chars().any(|c| c.is_ascii_alphabetic()) && has_romaji_fragment(text))
+}
+
 /// Mozc-style width/script annotation for a pure-kana candidate, or `None`
 /// if the text mixes scripts or contains kanji/punctuation. Used to label
 /// `あ` / `ア` / `ｱ` candidates in the conversion list.
@@ -141,6 +238,16 @@ impl InputMethodEngine {
                 0,
                 AnnotatedCandidate::new(prev_suggest_text, CandidateSource::Model),
             );
+        } else if candidates
+            .first()
+            .is_some_and(|c| c.source == CandidateSource::Model)
+            && let Some(at) = candidates.iter().position(|c| c.text == prev_suggest_text)
+        {
+            // Two model answers disagree (live conversion fell back to the
+            // light model, or judged a learned word differently): Space
+            // starts from the text on screen, not from another one.
+            let shown = candidates.remove(at);
+            candidates.insert(0, shown);
         }
 
         if candidates.is_empty() {
@@ -226,6 +333,14 @@ impl InputMethodEngine {
         let mut exact = Vec::new();
         let mut predictive = Vec::new();
         let mut seen = HashSet::new();
+        // かい → KAI: an English word or romaji spelling is not what a kana
+        // reading asks for. Marking them seen also keeps them out of the
+        // predictive pass below.
+        // ＠ readings list a character's skills, and some are English
+        // (WHITE FANG 465): keep them.
+        let drop_latin =
+            !self.config.alphabet_candidates && has_kana(reading) && !is_character_query(reading);
+        let wanted = |surface: &str| !(drop_latin && is_latin_only(surface));
 
         // Exact matches, user dictionary first — only when no romaji tail
         // is pending (an exact hit on the base would ignore the typed
@@ -241,7 +356,7 @@ impl InputMethodEngine {
                 if exact.len() >= limit {
                     break;
                 }
-                if seen.insert(cand.surface.clone()) {
+                if wanted(&cand.surface) && seen.insert(cand.surface.clone()) {
                     exact.push(AnnotatedCandidate::new(cand.surface.clone(), source));
                 }
             }
@@ -252,7 +367,8 @@ impl InputMethodEngine {
         // rides on the candidate so selecting it commits and records under
         // the right key.
         let constraint = self.tail_constraint(pending);
-        if reading.chars().count() >= min_prefix_chars
+        if self.config.prediction
+            && reading.chars().count() >= min_prefix_chars
             && !matches!(constraint, TailConstraint::Dead)
         {
             let mut budget = predictive_limit;
@@ -272,7 +388,7 @@ impl InputMethodEngine {
                     if budget == 0 || exact.len() + predictive.len() >= limit {
                         break;
                     }
-                    if seen.insert(m.candidate.surface.clone()) {
+                    if wanted(&m.candidate.surface) && seen.insert(m.candidate.surface.clone()) {
                         budget -= 1;
                         predictive.push(
                             AnnotatedCandidate::new(m.candidate.surface.clone(), source)
@@ -323,26 +439,96 @@ impl InputMethodEngine {
         // just means no model candidates: symbol-only and early keystrokes
         // still get dictionary/rewriter/fallback candidates. Loading here
         // synchronously would block the key-event thread on the download.
-        let candidates = self.model_candidates(reading, num_candidates);
+        // A ＠ lookup the user dictionaries answer (＠こいし) is a list, not
+        // text to convert: the model would only add ＠小石 / ＠Koiし.
+        let listed = is_character_query(reading)
+            && self
+                .dicts
+                .user
+                .as_ref()
+                .is_some_and(|d| d.exact_match_search(reading).is_some());
+        let candidates = if listed {
+            Vec::new()
+        } else {
+            self.model_candidates(reading, num_candidates)
+        };
 
         let hiragana = reading.to_string();
         let katakana = karukan_engine::hiragana_to_katakana(reading);
 
+        // What is preferred for the span the model converts (the whole
+        // reading unless it is long or starts with digits): the learned
+        // surface when the text on the left does not argue against it, a
+        // counter after a number (18さい → 18歳), and learned words inside
+        // the model's sentence. Live conversion asks the same questions of
+        // the same span, so Space confirms what was on screen.
+        let use_learning = learning == LearningLookup::Use;
+        let (prefix, span, span_lctx) = self.span_parts(reading);
+        let whole = prefix.is_empty();
+        let span_top: Option<String> = candidates
+            .first()
+            .and_then(|c| c.strip_prefix(prefix.as_str()))
+            .map(str::to_string);
+        let pick = if listed || span.is_empty() {
+            None
+        } else {
+            self.preferred_surface(&span, &span_lctx, span_top.as_deref(), use_learning)
+        };
+        let in_sentence = match (&pick, &span_top) {
+            (None, Some(top)) if !listed => {
+                self.respell_sentence(&span, &span_lctx, top, use_learning, ModelRole::Main)
+            }
+            _ => prefer::SentenceLearning::default(),
+        };
+        let learned_first = matches!(pick, Some((_, CandidateSource::Learning)));
+
         let mut builder = CandidateBuilder::new();
 
-        // 1. Learning cache candidates (highest priority).
-        //    Force-inserted so they win against duplicate text from later sources.
+        // 1. Learning cache candidates (highest priority), unless the
+        //    context argues against them: then the model's answer for this
+        //    context leads and they follow it (18|さい: 歳 before a learned 再).
         //    Skipped when the caller asks for a learning-free conversion (Tab key).
-        if learning == LearningLookup::Use {
+        //    Only exact matches go first: a learned reading that merely
+        //    starts with the typed one (るるはその for るる) is a past
+        //    sentence, not this word, and waits with the other predictive
+        //    candidates in step 4.
+        let mut learned_predictive = Vec::new();
+        let mut learned_exact = Vec::new();
+        if use_learning {
             for c in self.lookup_learning_candidates(reading) {
                 // Exact matches have reading == input reading; use None to avoid redundancy
                 let cand_reading = c.reading.filter(|r| r != reading);
-                builder.push_force(
-                    AnnotatedCandidate::new(c.text, CandidateSource::Learning)
-                        .with_reading(cand_reading),
-                );
+                let ac = AnnotatedCandidate::new(c.text, CandidateSource::Learning)
+                    .with_reading(cand_reading);
+                if ac.reading.is_some() {
+                    learned_predictive.push(ac);
+                } else if whole {
+                    learned_exact.push(ac);
+                } else {
+                    // A whole composition learned as it stands (18さい): the
+                    // span's judgement does not cover it.
+                    builder.push_force(ac);
+                }
             }
         }
+        if let Some((surface, source)) = &pick {
+            builder.push(AnnotatedCandidate::new(
+                format!("{prefix}{surface}"),
+                *source,
+            ));
+        }
+        if !learned_first
+            && !learned_exact.is_empty()
+            && let Some(best) = candidates.first()
+        {
+            builder.push(AnnotatedCandidate::new(
+                best.clone(),
+                CandidateSource::Model,
+            ));
+        }
+        for ac in learned_exact {
+            builder.push(ac);
+        }
 
         // 2. Exact user dictionary matches: what the user registered for
         //    this very reading outranks the model.
@@ -362,7 +548,236 @@ impl InputMethodEngine {
             builder.push(ac);
         }
 
-        // 3. Model inference results
+        // 3. Model inference results. With `alphabet_candidates = false` a
+        //    kana reading gets no Latin-only sentence from the model either
+        //    (るる → Lulu).
+        let drop_latin =
+            !self.config.alphabet_candidates && has_kana(reading) && !is_character_query(reading);
+        let mut candidates = candidates;
+        let swaps: Vec<String> = match candidates.first() {
+            // One word of the model's best sentence, swapped for its other
+            // dictionary spellings (何々の旅に → 何々の度に). The dictionaries
+            // below only match the whole reading, so inside a sentence these
+            // are the only dictionary alternatives there are.
+            Some(best) => self
+                .word_swap_candidates(reading, best, drop_latin)
+                .into_iter()
+                .filter(|t| !(drop_latin && is_unwanted_latin(reading, t)))
+                .collect(),
+            None => Vec::new(),
+        };
+        // Every other word of the sentence, in every spelling the
+        // dictionaries have for it (see `word_alternatives`).
+        let mut loose: HashSet<String> = HashSet::new();
+        let mut recuts: HashSet<String> = HashSet::new();
+        // What `kanji_preference` does not put first: another word or
+        // another cut is not "the same in kanji", and a word that is as
+        // good as always left in kana stays so (ありがとう).
+        let mut not_for_kanji_preference: HashSet<String> = HashSet::new();
+        let mut swaps = swaps;
+        // Those that may take the lead unasked, with the margin each may
+        // trail by and still do so (see `may_lead`).
+        let mut common: HashMap<String, f32> = HashMap::new();
+        if let Some(top) = &span_top
+            && !listed
+        {
+            let alternatives = self.word_alternatives(&span, top, drop_latin);
+            for (alternative, margin) in self.may_lead(&alternatives, ModelRole::Main) {
+                common.insert(format!("{prefix}{}", alternative.text), margin);
+            }
+            for alternative in alternatives {
+                let text = format!("{prefix}{}", alternative.text);
+                if !alternative.kana || alternative.kana_usual {
+                    not_for_kanji_preference.insert(text.clone());
+                }
+                if !alternative.kana {
+                    loose.insert(text.clone());
+                }
+                if !swaps.contains(&text) {
+                    swaps.push(text);
+                }
+            }
+            // The same kana cut into words at other places (くろきちょう:
+            // 黒き蝶 → 黒木町, 黒基調; see `lattice`), dealt in among the
+            // respellings so that a tight budget keeps some of each.
+            let mut recut: Vec<String> = Vec::new();
+            for found in self.lattice_alternatives(&span, top, drop_latin) {
+                let text = format!("{prefix}{}", found.text);
+                // A cut that holds a word the user chose before may lead
+                // as long as the model does not find it far-fetched.
+                if found.learned {
+                    common
+                        .entry(text.clone())
+                        .or_insert(prefer::LEARNED_RECUT_MARGIN);
+                }
+                if !swaps.contains(&text) {
+                    recut.push(text);
+                }
+            }
+            recuts.extend(recut.iter().cloned());
+            let mut recut = recut.into_iter();
+            let mut dealt: Vec<String> = Vec::new();
+            for (at, text) in std::mem::take(&mut swaps).into_iter().enumerate() {
+                dealt.push(text);
+                if at % 2 == 1 {
+                    dealt.extend(recut.next());
+                }
+            }
+            dealt.extend(recut);
+            swaps = dealt;
+        }
+        let answered = !candidates.is_empty();
+        candidates.retain(|t| !(drop_latin && is_unwanted_latin(reading, t)));
+        // Every answer was English (あっぷでーと → Update): the model's
+        // choice among the Japanese spellings stands in for it.
+        if answered && candidates.is_empty() && whole && !listed {
+            candidates.push(self.japanese_instead(&span, &span_lctx));
+        }
+        // The other beams, the swaps and the word alternatives are judged
+        // together by the main model: its likeliest first, and nothing it
+        // finds far-fetched next to its best answer (耳が主基です,
+        // で着ていない). A sentence it finds clearly more natural than its
+        // own first answer takes the lead — greedy decoding does not always
+        // find its likeliest sentence — and so does, with
+        // `kanji_preference`, one that writes more of the words in kanji
+        // without falling far behind (いろんな単語 → 色んな単語). Then the
+        // other words get their turn against the new leader
+        // (皮の箸 → 皮の橋 → 川の橋).
+        let mut swap_texts: HashSet<String> = swaps.iter().cloned().collect();
+        if let Some(best) = candidates.first().cloned() {
+            let mut pool = candidates.split_off(1);
+            for text in swaps {
+                if text != best && !pool.contains(&text) {
+                    pool.push(text);
+                }
+            }
+            // Scoring costs time in proportion to what is scored: a long
+            // sentence gets fewer alternatives than a short one.
+            let budget = (prefer::SCORE_BUDGET_CHARS / span.chars().count().max(1))
+                .clamp(prefer::MIN_SCORED, prefer::MAX_SCORED);
+            pool.truncate(budget);
+            let mut leader = best;
+            let mut passed: Vec<String> = Vec::new();
+            let mut ceiling = f32::NEG_INFINITY;
+            let mut known: HashMap<String, f32> = HashMap::new();
+            for round in 0..=prefer::MAX_RESPELL_ROUNDS {
+                let Some((top, ranked)) =
+                    self.rank_by_model(&prefix, &span, &span_lctx, &leader, pool.clone(), &loose)
+                else {
+                    break;
+                };
+                ceiling = ceiling.max(top);
+                known.insert(leader.clone(), top);
+                known.extend(ranked.iter().map(|(score, text)| (text.clone(), *score)));
+                pool = ranked.iter().map(|(_, text)| text.clone()).collect();
+                if round == prefer::MAX_RESPELL_ROUNDS || listed {
+                    break;
+                }
+                let more_natural = ranked
+                    .first()
+                    .filter(|(score, _)| *score >= ceiling + prefer::ADOPT_MARGIN);
+                let more_kanji = || {
+                    let margin = self.config.kanji_preference;
+                    let kanji = prefer::kanji_count(&leader);
+                    ranked.iter().find(|(score, text)| {
+                        margin > 0.0
+                            && *score >= ceiling - margin
+                            && prefer::kanji_count(text) > kanji
+                            && !not_for_kanji_preference.contains(text)
+                            && !recuts.contains(text)
+                    })
+                };
+                let unasked = || {
+                    ranked.iter().find(|(score, text)| {
+                        common
+                            .get(text)
+                            .is_some_and(|margin| *score >= ceiling - margin)
+                    })
+                };
+                let Some((score, next)) =
+                    more_natural.or_else(more_kanji).or_else(unasked).cloned()
+                else {
+                    break;
+                };
+                ceiling = ceiling.max(score);
+                pool.retain(|text| *text != next);
+                passed.insert(0, std::mem::replace(&mut leader, next));
+                if let Some(tail) = leader.strip_prefix(prefix.as_str()) {
+                    let alternatives = self.word_alternatives(&span, tail, drop_latin);
+                    common = self
+                        .may_lead(&alternatives, ModelRole::Main)
+                        .into_iter()
+                        .map(|(alternative, margin)| {
+                            (format!("{prefix}{}", alternative.text), margin)
+                        })
+                        .collect();
+                    for alternative in alternatives {
+                        let kana = alternative.kana;
+                        let text = format!("{prefix}{}", alternative.text);
+                        if text == leader || passed.contains(&text) || pool.contains(&text) {
+                            continue;
+                        }
+                        if !kana || alternative.kana_usual {
+                            not_for_kanji_preference.insert(text.clone());
+                        }
+                        if !kana {
+                            loose.insert(text.clone());
+                        }
+                        swap_texts.insert(text.clone());
+                        pool.push(text);
+                    }
+                }
+            }
+            // Behind the leader, everything in the model's order (what it
+            // could not score keeps its place at the end).
+            passed.extend(pool);
+            passed.sort_by(|a, b| {
+                let score = |text: &String| known.get(text).copied().unwrap_or(f32::NEG_INFINITY);
+                score(b).total_cmp(&score(a))
+            });
+            candidates.clear();
+            candidates.push(leader);
+            candidates.extend(passed);
+        }
+        // Learned words inside the model's sentence: ahead of it when the
+        // context accepts them, right behind it otherwise.
+        let mut respelled: Vec<String> = in_sentence
+            .alternatives
+            .iter()
+            .map(|s| format!("{prefix}{s}"))
+            .collect();
+        if let Some(sentence) = &in_sentence.accepted {
+            candidates.insert(0, format!("{prefix}{sentence}"));
+            respelled.insert(0, candidates[1].clone());
+        }
+        if !candidates.is_empty() {
+            let rest = candidates.split_off(1);
+            candidates.extend(respelled);
+            candidates.extend(rest);
+        }
+        // The dictionary's own order knows nothing of the text on the left:
+        // the model orders the first of the exact matches for this context,
+        // steadied by how common each word is, and the best of them goes
+        // ahead of the model's answer when that answer is just another of
+        // these words (ぼく: 僕 before 朴). Symbols and emoji that the
+        // dictionary files hold wait for the curated symbol table below
+        // (はーと: ♡ ♥ before 💓 💕 💖).
+        let (system_exact, pictographs): (Vec<_>, Vec<_>) = system_exact
+            .into_iter()
+            .partition(|c| c.text.chars().any(char::is_alphanumeric));
+        let system_exact = if whole && pending.is_empty() && !listed {
+            let top = candidates.first().cloned();
+            let (ordered, ahead) =
+                self.order_by_model(&span, &span_lctx, system_exact, top.as_deref());
+            if ahead && let Some(first) = ordered.first() {
+                swap_texts.insert(first.text.clone());
+                candidates.retain(|text| *text != first.text);
+                candidates.insert(0, first.text.clone());
+            }
+            ordered
+        } else {
+            system_exact
+        };
         if candidates.is_empty() {
             // No literal fallback in emoji mode: `:smile` must not outrank
             // the 😄 surfaced by the rewriter step below.
@@ -374,15 +789,56 @@ impl InputMethodEngine {
             }
         } else {
             for text in candidates {
-                builder.push(AnnotatedCandidate::new(text, CandidateSource::Model));
+                let source = if swap_texts.contains(&text) {
+                    CandidateSource::Dictionary
+                } else {
+                    CandidateSource::Model
+                };
+                builder.push(AnnotatedCandidate::new(text, source));
             }
         }
 
-        // 4. Exact system dictionary matches
-        for ac in system_exact {
+        // 4. Exact system dictionary matches (ordered above, by the model
+        //    and by how common each word is), then what was learned for a
+        //    longer reading.
+        for ac in system_exact.into_iter().chain(learned_predictive) {
             builder.push(ac);
         }
 
+        // The user's own words judge between the first answers (see
+        // `persona_judge`); what was learned for this very reading or
+        // stands in a user dictionary is not theirs to overrule.
+        if whole
+            && !listed
+            && prefix.is_empty()
+            && let Some(first) = builder.candidates.first()
+            && matches!(
+                first.source,
+                CandidateSource::Model | CandidateSource::Dictionary
+            )
+            && first.text != hiragana
+        {
+            let judged: Vec<String> = builder
+                .candidates
+                .iter()
+                .filter(|c| {
+                    matches!(
+                        c.source,
+                        CandidateSource::Model | CandidateSource::Dictionary
+                    ) && c.text != hiragana
+                })
+                .map(|c| c.text.clone())
+                .collect();
+            let texts: Vec<&str> = judged.iter().map(String::as_str).collect();
+            if let Some(winner) = self.persona_judge(&span, &span_lctx, &texts, ModelRole::Main)
+                && let Some(at) = builder.candidates.iter().position(|c| c.text == winner)
+            {
+                let mut winner = builder.candidates.remove(at);
+                winner.source = CandidateSource::Dictionary;
+                builder.candidates.insert(0, winner);
+            }
+        }
+
         // 5. Predictive matches, user dictionary first
         for ac in dictionary.predictive {
             builder.push(ac);
@@ -405,12 +861,21 @@ impl InputMethodEngine {
         }
         // Rewriters run on the typed reading only; running them on other
         // sources' candidates would emit variants nobody asked for.
-        for (variant, description) in self.rewriter_variants(reading) {
+        // Plain symbols before playing cards and emoji: ♡ ♥ ❤ lead for はーと.
+        let emoji_mode = self.mode.current() == InputMode::Emoji;
+        let (plain, astral): (Vec<_>, Vec<_>) = self
+            .rewriter_variants(reading)
+            .into_iter()
+            .partition(|(variant, _)| emoji_mode || variant.chars().all(|c| (c as u32) < 0x1_0000));
+        for (variant, description) in plain.into_iter().chain(astral) {
             builder.push(
                 AnnotatedCandidate::new(variant, CandidateSource::Rewriter)
                     .with_description(description),
             );
         }
+        for ac in pictographs {
+            builder.push(ac);
+        }
 
         // 8. Back-fill descriptions. Symbol names are Fallback-only —
         //    model/dict/learning candidates must not inherit labels like
@@ -430,7 +895,11 @@ impl InputMethodEngine {
                 .map(str::to_string);
         }
 
-        builder.into_candidates()
+        let mut list = builder.into_candidates();
+        if self.mode.current() != InputMode::Emoji && !listed {
+            lift_symbols(&mut list);
+        }
+        list
     }
 
     /// Look up learning cache candidates for a reading (exact + prefix match, max 3).
@@ -477,7 +946,11 @@ impl InputMethodEngine {
         }
 
         // Prefix match (predictive), narrowed to the kana the tail can
-        // still become — mirrors the dictionary's expanded search
+        // still become — mirrors the dictionary's expanded search. Off with
+        // `prediction = false`: あ must not offer a learned あわせて.
+        if !self.config.prediction {
+            return candidates;
+        }
         for (full_reading, surface, _score) in cache.prefix_lookup(reading) {
             if candidates.len() >= max {
                 break;
@@ -689,10 +1162,14 @@ impl InputMethodEngine {
                     }
                 }
 
-                // A printable character refines instead of committing:
-                // the reading grows and the suggestion rewrites in place,
-                // keeping any active source filter.
+                // A printable character either commits the selection and
+                // starts the next composition (`commit_on_input`), or
+                // refines: the reading grows and the suggestion rewrites in
+                // place, keeping any active source filter.
                 if key.to_char().is_some() && !key.modifiers.control_key {
+                    if self.commits_on_input() {
+                        return self.commit_and_continue(key);
+                    }
                     return self.refine_through_composing(key);
                 }
 
@@ -704,6 +1181,57 @@ impl InputMethodEngine {
         }
     }
 
+    /// Whether a printable keystroke commits instead of refining: only with
+    /// `commit_on_input` on, and never inside a narrowed source view or the
+    /// emoji picker — those are searches, where typing narrows the query.
+    fn commits_on_input(&self) -> bool {
+        self.config.commit_on_input
+            && self.state.filter().is_none()
+            && self.mode.current() != InputMode::Emoji
+    }
+
+    /// Commit the selected candidate exactly as Enter does (learning record
+    /// included), then feed `key` to the Empty state as the first keystroke
+    /// of the next composition — the MS-IME / mozc flow. The committed text
+    /// is appended to the left context: the frontend captures the editor's
+    /// surrounding text only when a key arrives in the Empty state, which
+    /// this keystroke never does, so without it the next composition would
+    /// be converted against the stale pre-commit context.
+    fn commit_and_continue(&mut self, key: &KeyEvent) -> EngineResult {
+        let committed = self.commit_conversion();
+        let Some(text) = committed.actions.iter().find_map(|action| match action {
+            EngineAction::Commit(text) => Some(text.clone()),
+            _ => None,
+        }) else {
+            // Nothing to commit (an empty selection): keep the old behaviour.
+            return self.refine_through_composing(key);
+        };
+        self.extend_left_context(&text);
+        // A new word starts here, like the first key in the Empty state.
+        self.metrics.adaptive_use_light_model = false;
+        let next = self.process_key_empty(key);
+        // The commit has been made either way; if the Empty state declines
+        // the key, it reaches the application after the committed text.
+        EngineResult {
+            consumed: next.consumed,
+            actions: committed.actions.into_iter().chain(next.actions).collect(),
+        }
+    }
+
+    /// Append just-committed text to the left surrounding context, keeping
+    /// the right side. Goes through `set_surrounding_context`, so the
+    /// current-line cut, the whitespace rule and the length cap all apply.
+    fn extend_left_context(&mut self, committed: &str) {
+        let (left, right) = match &self.surrounding_context {
+            Some(context) => (
+                context.left.clone().unwrap_or_default(),
+                context.right.clone().unwrap_or_default(),
+            ),
+            None => (String::new(), String::new()),
+        };
+        self.set_surrounding_context(&format!("{left}{committed}"), &right);
+    }
+
     /// Feed a refining keystroke (printable char, Backspace) through the
     /// composing path, then re-enter the conversion with the previous
     /// source filter if one was active. With a filter the composing render
@@ -779,8 +1307,10 @@ impl InputMethodEngine {
         if self.mode.current() == InputMode::Emoji {
             return;
         }
+        let lctx = self.truncate_context_for_api();
+        let (key, surface) = prefer::learning_key(reading, surface, &lctx);
         if let Some(cache) = &mut self.learning {
-            cache.record(reading, surface);
+            cache.record_chosen(&key, &surface);
         }
     }
 
@@ -788,6 +1318,7 @@ impl InputMethodEngine {
     /// composition.
     pub(super) fn finish_conversion(&mut self, text: &str, reading: &Option<String>) {
         if let Some(reading) = reading {
+            self.learn_word_choice(reading, text);
             self.record_learning(reading, text);
         }
         self.end_composition();
@@ -839,10 +1370,17 @@ impl InputMethodEngine {
         let Some(reading) = self.state.reading().map(str::to_string) else {
             return EngineResult::consumed();
         };
-        let removed = self
-            .learning
-            .as_mut()
-            .is_some_and(|cache| cache.remove_suggestion(&reading, &surface));
+        // The entry may be a counter learned after a number (see
+        // `prefer::learning_key`): the same row, under its own key.
+        let lctx = self.truncate_context_for_api();
+        let (number_key, number_surface) = prefer::learning_key(&reading, &surface, &lctx);
+        let marked = format!("{}{reading}", prefer::NUMBER_MARK);
+        let removed = self.learning.as_mut().is_some_and(|cache| {
+            let plain = cache.remove_suggestion(&reading, &surface);
+            let keyed = cache.remove_suggestion(&number_key, &number_surface);
+            let after_number = cache.remove_suggestion(&marked, &surface);
+            plain || keyed || after_number
+        });
         if !removed {
             return EngineResult::consumed();
         }
diff --git a/karukan-im/core/src/core/engine/display.rs b/karukan-im/core/src/core/engine/display.rs
index 1046f26..1adf017 100644
--- a/karukan-im/core/src/core/engine/display.rs
+++ b/karukan-im/core/src/core/engine/display.rs
@@ -384,13 +384,24 @@ impl InputMethodEngine {
 
     /// Truncate context to safe size for API calls
     pub(super) fn truncate_context_for_api(&self) -> String {
-        match self
-            .surrounding_context
-            .as_ref()
-            .and_then(|ctx| ctx.left.as_deref())
-        {
-            Some(left) => self.truncate_context(left),
-            None => String::new(),
+        match &self.surrounding_context {
+            Some(ctx) => ctx
+                .left
+                .as_deref()
+                .map(|left| self.truncate_context(left))
+                .unwrap_or_default(),
+            // The editor reported nothing on either side: it cannot, or
+            // the line is empty. What the engine itself just committed
+            // there is the context (empty again after Enter or a caret
+            // move, see `OwnContext::follow`).
+            None => {
+                let own = self.own_context.text();
+                if own.trim().is_empty() {
+                    String::new()
+                } else {
+                    self.truncate_context(own)
+                }
+            }
         }
     }
 
diff --git a/karukan-im/core/src/core/engine/init.rs b/karukan-im/core/src/core/engine/init.rs
index aa0ca67..9dafaab 100644
--- a/karukan-im/core/src/core/engine/init.rs
+++ b/karukan-im/core/src/core/engine/init.rs
@@ -1,6 +1,8 @@
 //! Engine initialization (model loading, dictionary setup)
 
-use std::sync::mpsc;
+use std::path::{Path, PathBuf};
+use std::sync::{Arc, Mutex, Weak, mpsc};
+use std::time::SystemTime;
 
 use anyhow::{Context, Result};
 use karukan_engine::ModelSource;
@@ -10,15 +12,6 @@ use crate::config::settings::StrategyMode;
 
 use super::*;
 
-/// Process-global cache of the merged user dictionary.
-///
-/// The merged dictionary (potentially several large TSVs) takes seconds to
-/// load and merge. Karukan creates one engine per input context; without
-/// this cache, every new context (window/field switch) re-read and
-/// re-merged all dictionaries.
-static USER_DICT_CACHE: std::sync::OnceLock<Option<std::sync::Arc<Dictionary>>> =
-    std::sync::OnceLock::new();
-
 /// Converters produced by the background model-loading thread, handed to the
 /// engine through the `model_loading` channel.
 pub(super) struct LoadedConverters {
@@ -198,15 +191,18 @@ impl InputMethodEngine {
             return;
         }
 
-        match Dictionary::load(&path) {
-            Ok(dict) => {
-                debug!("System dictionary loaded from {:?}", path);
-                self.dicts.system = Some(std::sync::Arc::new(dict));
-            }
-            Err(e) => {
-                debug!("Failed to load system dictionary from {:?}: {}", path, e);
-            }
-        }
+        let key = vec![file_stamp(&path)];
+        self.dicts.system =
+            shared_dictionary(&SYSTEM_DICT, key, || match Dictionary::load(&path) {
+                Ok(dict) => {
+                    debug!("System dictionary loaded from {:?}", path);
+                    Some(dict)
+                }
+                Err(e) => {
+                    debug!("Failed to load system dictionary from {:?}: {}", path, e);
+                    None
+                }
+            });
     }
 
     /// Initialize the learning cache from disk.
@@ -260,12 +256,6 @@ impl InputMethodEngine {
             return;
         }
 
-        if let Some(cached) = USER_DICT_CACHE.get() {
-            debug!("User dictionaries resolved from process-level cache (no reload)");
-            self.dicts.user = cached.clone();
-            return;
-        }
-
         let Some(dir) = Settings::user_dict_dir() else {
             debug!("Could not determine user dictionary directory");
             return;
@@ -297,40 +287,84 @@ impl InputMethodEngine {
         // Sort for deterministic load order (alphabetical)
         paths.sort();
 
-        let mut dicts = Vec::new();
-        for path in &paths {
-            match Dictionary::load_auto(path) {
-                Ok(dict) => {
-                    debug!("User dictionary loaded from {:?}", path);
-                    dicts.push(dict);
+        let key = paths.iter().map(|path| file_stamp(path)).collect();
+        self.dicts.user = shared_dictionary(&USER_DICTS, key, || {
+            let mut dicts = Vec::new();
+            for path in &paths {
+                match Dictionary::load_auto(path) {
+                    Ok(dict) => {
+                        debug!("User dictionary loaded from {:?}", path);
+                        dicts.push(dict);
+                    }
+                    Err(e) => {
+                        debug!("Failed to load user dictionary from {:?}: {}", path, e);
+                    }
+                }
+            }
+
+            if dicts.is_empty() {
+                return None;
+            }
+
+            match Dictionary::merge(dicts) {
+                Ok(Some(merged)) => {
+                    debug!(
+                        "User dictionaries merged successfully ({} files from {:?})",
+                        paths.len(),
+                        dir
+                    );
+                    Some(merged)
                 }
+                Ok(None) => None,
                 Err(e) => {
-                    debug!("Failed to load user dictionary from {:?}: {}", path, e);
+                    debug!("Failed to merge user dictionaries: {}", e);
+                    None
                 }
             }
-        }
+        });
+    }
+}
 
-        if dicts.is_empty() {
-            return;
-        }
+/// Identity of a dictionary file as loaded: path, mtime and size. A rebuilt
+/// file gets a new stamp, so engines created afterwards load the new copy.
+type FileStamp = (PathBuf, Option<SystemTime>, u64);
+
+fn file_stamp(path: &Path) -> FileStamp {
+    let meta = std::fs::metadata(path).ok();
+    (
+        path.to_path_buf(),
+        meta.as_ref().and_then(|m| m.modified().ok()),
+        meta.map_or(0, |m| m.len()),
+    )
+}
 
-        match Dictionary::merge(dicts) {
-            Ok(Some(merged)) => {
-                debug!(
-                    "User dictionaries merged successfully ({} files from {:?})",
-                    paths.len(),
-                    dir
-                );
-                let merged = std::sync::Arc::new(merged);
-                self.dicts.user = Some(merged.clone());
-                let _ = USER_DICT_CACHE.set(Some(merged));
-            }
-            Ok(None) => {
-                let _ = USER_DICT_CACHE.set(None);
-            }
-            Err(e) => {
-                debug!("Failed to merge user dictionaries: {}", e);
-            }
-        }
+/// The last dictionary loaded under a key, held weakly: it stays shared
+/// while any engine uses it and is freed with the last one.
+type DictSlot = Mutex<Option<(Vec<FileStamp>, Weak<Dictionary>)>>;
+
+/// fcitx5 creates one engine per input context, and every engine used to
+/// load its own copy of the dictionaries on its first key — hundreds of MB
+/// per window for a large system dictionary, and a stall on the first key
+/// of every new window. Engines in one process now share a single copy.
+static SYSTEM_DICT: DictSlot = Mutex::new(None);
+static USER_DICTS: DictSlot = Mutex::new(None);
+
+/// Return the dictionary cached under `key`, or run `load` and cache it.
+/// The slot stays locked while loading, so engines initialising at the
+/// same time wait for one load instead of each doing their own.
+fn shared_dictionary(
+    slot: &DictSlot,
+    key: Vec<FileStamp>,
+    load: impl FnOnce() -> Option<Dictionary>,
+) -> Option<Arc<Dictionary>> {
+    let mut slot = slot.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
+    if let Some((cached_key, cached)) = slot.as_ref()
+        && *cached_key == key
+        && let Some(dict) = cached.upgrade()
+    {
+        return Some(dict);
     }
+    let dict = Arc::new(load()?);
+    *slot = Some((key, Arc::downgrade(&dict)));
+    Some(dict)
 }
diff --git a/karukan-im/core/src/core/engine/input.rs b/karukan-im/core/src/core/engine/input.rs
index 90f4a02..10dd7ce 100644
--- a/karukan-im/core/src/core/engine/input.rs
+++ b/karukan-im/core/src/core/engine/input.rs
@@ -32,8 +32,11 @@ impl InputMethodEngine {
         // Auto-suggest via chunked conversion. Skipped in alphabet mode
         // unless the buffer still contains kana (mode switched mid-word),
         // so live conversion stays alive on a mixed reading.
+        // ＠こいし is a lookup, not text: no live conversion (＠恋し), so the
+        // preedit keeps the kana and the dictionary's list is shown.
         let convert = !self.suppress_suggest
             && !full_reading.is_empty()
+            && !super::conversion::is_character_query(&full_reading)
             && (self.mode.current() != InputMode::Alphabet
                 || karukan_engine::contains_kana(&full_reading));
         let candidates = if convert {
@@ -393,7 +396,7 @@ impl InputMethodEngine {
 
     /// Commit the current composition (Enter).
     pub(super) fn commit_composing(&mut self) -> EngineResult {
-        let (reading, text) = self.resolve_composing_commit();
+        let (_, text) = self.resolve_composing_commit();
 
         if text.is_empty() {
             self.end_composition();
@@ -402,7 +405,10 @@ impl InputMethodEngine {
                 .with_action(EngineAction::HideAuxText);
         }
 
-        self.record_learning(&reading, &text);
+        // Nothing is learned here: Enter on the live conversion is the
+        // engine's own answer coming back, not a choice. Learning it filled
+        // the history with sentences and bare kana (わたし → わたし) that
+        // then outranked what the user really picked.
         self.end_composition();
 
         // HideCandidates is required here: the auto-suggest/live-conversion
diff --git a/karukan-im/core/src/core/engine/lattice.rs b/karukan-im/core/src/core/engine/lattice.rs
new file mode 100644
index 0000000..0da96fd
--- /dev/null
+++ b/karukan-im/core/src/core/engine/lattice.rs
@@ -0,0 +1,380 @@
+//! Other ways to cut a reading into words.
+//!
+//! The model writes a sentence one way (くろきちょう → 黒き蝶), and the word
+//! alternatives respell its words one at a time (黒き腸). What neither
+//! reaches is the same kana cut at other places: 黒木|町, 黒|基調. Here the
+//! reading — all of it when short, each phrase and each pair of phrases
+//! otherwise — is laid out as a lattice of dictionary words, the cheapest
+//! paths through it are taken, and the caller lets the model judge them
+//! with everything else.
+//!
+//! The lattice knows how common each word is (the costs in the system
+//! dictionary) but not how well two words go together, so its order means
+//! little: it only has to put the plausible cuts among its first few. A
+//! fixed cost per word stands in for the missing connection costs and
+//! favours fewer, longer words.
+
+use std::collections::HashMap;
+use std::ops::Range;
+
+use super::prefer::{self, Script, aligns, script};
+use super::*;
+
+/// The longest reading looked up as one word.
+const MAX_WORD_CHARS: usize = 10;
+/// Spellings taken per reading from the system dictionary, commonest first.
+const SPELLINGS: usize = 4;
+/// Partial paths kept per position, and of those, per way of cutting.
+const BEAM: usize = 48;
+const PER_CUT: usize = 3;
+/// Added per word (see the module comment).
+const WORD_COST: f32 = 1800.0;
+/// What the user chose before, a user-dictionary word, and a dictionary
+/// word without a frequency.
+const LEARNED_COST: f32 = 500.0;
+const USER_COST: f32 = 2500.0;
+const UNKNOWN_COST: f32 = 9000.0;
+/// Kana words in a row a path may hold (を|し|て; see `lattice_paths`).
+const MAX_KANA_RUN: usize = 3;
+/// The shortest katakana word taken from the system dictionary.
+const MIN_KATAKANA_CHARS: usize = 3;
+/// A reading up to this long is cut as a whole; longer ones phrase by
+/// phrase, where a phrase (or two together) is up to `MAX_REGION_CHARS`.
+const MAX_WHOLE_CHARS: usize = 16;
+const MAX_REGION_CHARS: usize = 14;
+/// A path this much dearer than the cheapest is no cut worth showing
+/// (ハー|と next to ハート).
+const MAX_SPREAD: f32 = 5000.0;
+/// Paths taken for the whole reading and for each region, and in all.
+const WHOLE_PATHS: usize = 12;
+const REGION_PATHS: usize = 4;
+const MAX_LATTICE_ALTERNATIVES: usize = 36;
+
+/// A word of the lattice: a spelling, its cost, and whether the user
+/// chose it before.
+struct Word {
+    surface: String,
+    cost: f32,
+    learned: bool,
+}
+
+/// A partial path: its cost, its text, where it was cut, its words that
+/// are written with kanji (reading and spelling), and those of them that
+/// are the user's own choice.
+#[derive(Clone)]
+struct Path {
+    cost: f32,
+    text: String,
+    cuts: Vec<usize>,
+    words: Vec<(String, String)>,
+    learned: Vec<String>,
+    /// How many kana words it ends in.
+    kana_run: usize,
+}
+
+/// A sentence with one stretch cut into words another way.
+pub(super) struct Recut {
+    pub text: String,
+    /// The words of that stretch written with kanji: reading and spelling.
+    pub words: Vec<(String, String)>,
+    /// Whether one of them is what the user chose for its reading before
+    /// and the sentence does not have.
+    pub learned: bool,
+}
+
+impl InputMethodEngine {
+    /// `sentence` (the model's conversion of `reading`) with one stretch of
+    /// it cut into words another way, likeliest stretches first. Empty
+    /// without the frequency data (`word_prior = 0`).
+    pub(super) fn lattice_alternatives(
+        &self,
+        reading: &str,
+        sentence: &str,
+        skip_latin: bool,
+    ) -> Vec<Recut> {
+        if self.config.word_prior <= 0.0 || conversion::is_character_query(reading) {
+            return Vec::new();
+        }
+        let r: Vec<char> = reading.chars().collect();
+        let s: Vec<char> = sentence.chars().collect();
+        if r.len() < 2 || r.iter().any(|c| script(*c) != Script::Hira && *c != 'ー') {
+            return Vec::new();
+        }
+        let mut words: HashMap<String, Vec<Word>> = HashMap::new();
+        // (sentence range, reading range, paths wanted)
+        let mut regions: Vec<(Range<usize>, Range<usize>, usize)> = Vec::new();
+        if r.len() <= MAX_WHOLE_CHARS {
+            regions.push((0..s.len(), 0..r.len(), WHOLE_PATHS));
+        }
+        if let Some(phrases) = phrases(&s, &r) {
+            for (at, (text, read)) in phrases.iter().enumerate() {
+                let mut add = |text: Range<usize>, read: Range<usize>| {
+                    let whole = read.len() == r.len() && r.len() <= MAX_WHOLE_CHARS;
+                    if (2..=MAX_REGION_CHARS).contains(&read.len()) && !whole {
+                        regions.push((text, read, REGION_PATHS));
+                    }
+                };
+                add(text.clone(), read.clone());
+                if let Some((next_text, next_read)) = phrases.get(at + 1) {
+                    add(text.start..next_text.end, read.start..next_read.end);
+                }
+            }
+        }
+        let mut found: Vec<Vec<Recut>> = Vec::new();
+        for (text, read, wanted) in regions {
+            let current: String = s[text.clone()].iter().collect();
+            let before: String = s[..text.start].iter().collect();
+            let after: String = s[text.end..].iter().collect();
+            let mut paths = self.lattice_paths(&r[read], skip_latin, &mut words);
+            // What is wanted here is another cut. The sentence's own cut
+            // with other spellings is what the word alternatives are for,
+            // and of every other cut the cheapest spelling comes before
+            // any second one.
+            if let Some(own) = paths.iter().find(|path| path.text == current) {
+                let cuts = own.cuts.clone();
+                paths.retain(|path| path.cuts != cuts);
+            }
+            let mut turn: Vec<usize> = Vec::with_capacity(paths.len());
+            for (at, path) in paths.iter().enumerate() {
+                turn.push(paths[..at].iter().filter(|p| p.cuts == path.cuts).count());
+            }
+            let mut order: Vec<usize> = (0..paths.len()).collect();
+            order.sort_by_key(|&at| turn[at]);
+            let mut paths: Vec<Option<Path>> = paths.into_iter().map(Some).collect();
+            let paths: Vec<Recut> = order
+                .into_iter()
+                .filter_map(|at| paths[at].take())
+                .filter(|path| path.text != current)
+                .take(wanted)
+                .map(|path| Recut {
+                    text: format!("{before}{}{after}", path.text),
+                    words: path.words,
+                    learned: path
+                        .learned
+                        .iter()
+                        .any(|word| !sentence.contains(word.as_str())),
+                })
+                .collect();
+            if !paths.is_empty() {
+                found.push(paths);
+            }
+        }
+        // In turns, so that every stretch gets its say.
+        let mut out: Vec<Recut> = Vec::new();
+        let longest = found.iter().map(Vec::len).max().unwrap_or(0);
+        let mut found: Vec<_> = found.into_iter().map(Vec::into_iter).collect();
+        'all: for _ in 0..longest {
+            for paths in &mut found {
+                if let Some(recut) = paths.next()
+                    && recut.text != sentence
+                    && !out.iter().any(|known| known.text == recut.text)
+                {
+                    out.push(recut);
+                    if out.len() >= MAX_LATTICE_ALTERNATIVES {
+                        break 'all;
+                    }
+                }
+            }
+        }
+        out
+    }
+
+    /// The cheapest ways to write `r` as dictionary words, at most
+    /// `PER_CUT` per way of cutting it, cheapest first. Only those with a
+    /// kanji or katakana in them: the kana as typed is no conversion.
+    fn lattice_paths(
+        &self,
+        r: &[char],
+        skip_latin: bool,
+        words: &mut HashMap<String, Vec<Word>>,
+    ) -> Vec<Path> {
+        let mut best: Vec<Vec<Path>> = vec![Vec::new(); r.len() + 1];
+        best[0].push(Path {
+            cost: 0.0,
+            text: String::new(),
+            cuts: Vec::new(),
+            words: Vec::new(),
+            learned: Vec::new(),
+            kana_run: 0,
+        });
+        for end in 1..=r.len() {
+            let mut here: Vec<Path> = Vec::new();
+            for start in end.saturating_sub(MAX_WORD_CHARS)..end {
+                if best[start].is_empty() {
+                    continue;
+                }
+                let reading: String = r[start..end].iter().collect();
+                let options = words
+                    .entry(reading.clone())
+                    .or_insert_with(|| self.lattice_words(&reading, skip_latin));
+                for word in options.iter() {
+                    let kana = word.surface.chars().all(|c| script(c) == Script::Hira);
+                    for path in &best[start] {
+                        // は|に|も|… : kana cut into ever smaller words is
+                        // cheap, says nothing, and crowds out the rest.
+                        if kana && path.kana_run >= MAX_KANA_RUN {
+                            continue;
+                        }
+                        let mut cuts = path.cuts.clone();
+                        cuts.push(end);
+                        let mut spelled = path.words.clone();
+                        if prefer::kanji_count(&word.surface) > 0 {
+                            spelled.push((reading.clone(), word.surface.clone()));
+                        }
+                        let mut learned = path.learned.clone();
+                        if word.learned {
+                            learned.push(word.surface.clone());
+                        }
+                        here.push(Path {
+                            cost: path.cost + word.cost + WORD_COST,
+                            text: format!("{}{}", path.text, word.surface),
+                            cuts,
+                            words: spelled,
+                            learned,
+                            kana_run: if kana { path.kana_run + 1 } else { 0 },
+                        });
+                    }
+                }
+            }
+            here.sort_by(|a, b| a.cost.total_cmp(&b.cost));
+            let mut kept: Vec<Path> = Vec::new();
+            for path in here {
+                if kept.len() >= BEAM {
+                    break;
+                }
+                if kept.iter().any(|k| k.text == path.text)
+                    || kept.iter().filter(|k| k.cuts == path.cuts).count() >= PER_CUT
+                {
+                    continue;
+                }
+                kept.push(path);
+            }
+            best[end] = kept;
+        }
+        let paths = best.pop().unwrap_or_default();
+        let ceiling = paths.first().map_or(0.0, |cheapest| cheapest.cost) + MAX_SPREAD;
+        paths
+            .into_iter()
+            .filter(|path| {
+                path.cost <= ceiling
+                    && path
+                        .text
+                        .chars()
+                        .any(|c| matches!(script(c), Script::Kanji | Script::Kata))
+            })
+            .collect()
+    }
+
+    /// The words that read exactly `reading`, each with its cost: what the
+    /// user chose before, the user dictionaries, the commonest of the
+    /// system dictionary, and the kana itself where it is a function word
+    /// (は, から, です). Kana no dictionary vouches for is not a word: a
+    /// reading that cannot be cut without it has no path.
+    fn lattice_words(&self, reading: &str, skip_latin: bool) -> Vec<Word> {
+        let mut out: Vec<Word> = Vec::new();
+        let add = |surface: &str, cost: f32, learned: bool, out: &mut Vec<Word>| {
+            if surface.is_empty()
+                || !surface.chars().any(char::is_alphanumeric)
+                || (skip_latin && conversion::is_unwanted_latin(reading, surface))
+            {
+                return;
+            }
+            match out.iter_mut().find(|word| word.surface == surface) {
+                Some(known) => known.cost = known.cost.min(cost),
+                None => out.push(Word {
+                    surface: surface.to_string(),
+                    cost,
+                    learned,
+                }),
+            }
+        };
+        if let Some(cache) = &self.learning {
+            for (surface, _) in cache.preferred(reading).into_iter().take(2) {
+                add(&surface, LEARNED_COST, surface != reading, &mut out);
+            }
+        }
+        if let Some(found) = self
+            .dicts
+            .user
+            .as_ref()
+            .and_then(|user| user.exact_match_search(reading))
+        {
+            for candidate in found.candidates.iter().take(SPELLINGS) {
+                add(&candidate.surface, USER_COST, false, &mut out);
+            }
+        }
+        if let Some(system) = self.dicts.system.as_ref() {
+            if let Some(found) = system.exact_match_search(reading) {
+                let mut known: Vec<(&str, f32)> = found
+                    .candidates
+                    .iter()
+                    .map(|c| {
+                        let cost = if c.score < prefer::UNKNOWN_WORD_COST {
+                            c.score
+                        } else {
+                            UNKNOWN_COST
+                        };
+                        (c.surface.as_str(), cost)
+                    })
+                    .collect();
+                known.sort_by(|a, b| a.1.total_cmp(&b.1));
+                let mut taken = 0;
+                for (surface, cost) in known {
+                    if taken >= SPELLINGS {
+                        break;
+                    }
+                    // Words written with kanji: cutting the kana another
+                    // way is about which kanji words it holds. Short
+                    // katakana only adds noise (はー|と → ハーと); a longer
+                    // word the frequency data knows is a word (イルカ).
+                    // The kana itself is a word where the data knows it as
+                    // one (ここ, すごく); as a function word it comes below.
+                    let kana_word = surface == reading && cost < UNKNOWN_COST;
+                    let katakana_word = cost < UNKNOWN_COST
+                        && surface.chars().count() >= MIN_KATAKANA_CHARS
+                        && surface.chars().all(|c| script(c) == Script::Kata);
+                    if prefer::kanji_count(surface) == 0 && !kana_word && !katakana_word {
+                        continue;
+                    }
+                    add(surface, cost, false, &mut out);
+                    taken += 1;
+                }
+            }
+            if let Some(mark) =
+                system.exact_match_search(&format!("{}{reading}", prefer::KANA_MARK))
+                && let Some(kana) = mark.candidates.first()
+            {
+                add(reading, kana.score, false, &mut out);
+            }
+        }
+        out
+    }
+}
+
+/// `s` (a conversion of `r`) as phrases — a run of anything but hiragana
+/// with the hiragana after it (黒き, 蝶) — each with the stretch of the
+/// reading it stands for. `None` when the two cannot be lined up.
+fn phrases(s: &[char], r: &[char]) -> Option<Vec<(Range<usize>, Range<usize>)>> {
+    let mut starts: Vec<usize> = vec![0];
+    for at in 1..s.len() {
+        if script(s[at]) != Script::Hira && script(s[at - 1]) == Script::Hira {
+            starts.push(at);
+        }
+    }
+    let mut reads: Vec<usize> = vec![0];
+    for &at in &starts[1..] {
+        let from = *reads.last()? + 1;
+        let read = (from..r.len())
+            .find(|&read| aligns(&s[..at], &r[..read]) && aligns(&s[at..], &r[read..]))?;
+        reads.push(read);
+    }
+    starts.push(s.len());
+    reads.push(r.len());
+    Some(
+        starts
+            .windows(2)
+            .zip(reads.windows(2))
+            .map(|(text, read)| (text[0]..text[1], read[0]..read[1]))
+            .collect(),
+    )
+}
diff --git a/karukan-im/core/src/core/engine/mod.rs b/karukan-im/core/src/core/engine/mod.rs
index 4330697..537d4ea 100644
--- a/karukan-im/core/src/core/engine/mod.rs
+++ b/karukan-im/core/src/core/engine/mod.rs
@@ -13,9 +13,12 @@ mod guard;
 mod init;
 mod input;
 mod input_buffer;
+mod lattice;
 mod mode;
 mod model;
+mod prefer;
 mod strategy;
+mod swap;
 mod types;
 
 pub use types::*;
@@ -124,6 +127,17 @@ pub struct InputMethodEngine {
     converters: Converters,
     /// Surrounding text context from the editor (text around cursor)
     surrounding_context: Option<SurroundingContext>,
+    /// What the engine itself has put at the caret since the caret last
+    /// moved: the text it committed and the keys it let through. An
+    /// editor that reports no surrounding text (a terminal, many
+    /// toolkits) would otherwise leave every composition without any
+    /// context at all — the sentence just committed included.
+    /// The user's own words from the learning record (`auto_persona`; see
+    /// `persona_judge`), as of the learning revision in
+    /// `persona_revision`.
+    learned_persona: String,
+    persona_revision: Option<u64>,
+    own_context: prefer::OwnContext,
     /// Engine configuration
     config: EngineConfig,
     /// Conversion timing and adaptive model metrics
@@ -151,6 +165,9 @@ pub struct InputMethodEngine {
     /// LRU cache of model conversion results keyed by reading + lctx +
     /// strategy. Content-addressed, so it survives commits and resets.
     conversion_cache: ConversionCache,
+    /// Model log-probabilities already computed (see `prefer`): what the
+    /// model thinks of a surface it did not necessarily propose.
+    score_cache: prefer::ScoreCache,
     /// Suppresses the auto-suggest model call while a conversion detours
     /// through the composing path and throws the render away. Owned by
     /// `in_composing`, which sets and clears it around the one call.
@@ -192,6 +209,10 @@ impl InputMethodEngine {
             chunks: Vec::new(),
             chunk_breaks: Vec::new(),
             conversion_cache: ConversionCache::default(),
+            score_cache: prefer::ScoreCache::default(),
+            own_context: prefer::OwnContext::default(),
+            learned_persona: String::new(),
+            persona_revision: None,
             suppress_suggest: false,
             shown_suggestions: CandidateList::default(),
             dicts: Dictionaries::default(),
@@ -285,6 +306,7 @@ impl InputMethodEngine {
         self.mode = ModeState::default();
         self.clear_composition();
         self.metrics = ConversionMetrics::default();
+        self.own_context.clear();
     }
 
     /// Drop all composition-scoped state in one place: the input buffer, the
@@ -596,7 +618,9 @@ impl InputMethodEngine {
 
     /// Process a key event
     pub fn process_key(&mut self, key: &KeyEvent) -> EngineResult {
+        self.refresh_persona();
         let result = self.dispatch_key(key);
+        self.own_context.follow(key, &result);
         self.hide_candidate_window(result)
     }
 
@@ -630,6 +654,15 @@ impl InputMethodEngine {
             return EngineResult::not_consumed();
         }
 
+        // 無変換: switch the kana type of the composition (bare press only,
+        // like 変換 — a modified chord may be an app or fcitx5 shortcut)
+        if key.keysym == Keysym::MUHENKAN
+            && !key.modifiers.any()
+            && let Some(result) = self.switch_kana_type()
+        {
+            return result;
+        }
+
         // Ctrl+Shift+L: toggle live conversion (works in all states)
         if key.modifiers.control_key
             && key.modifiers.shift_key
@@ -711,8 +744,8 @@ impl InputMethodEngine {
         let text = match &self.state {
             InputState::Empty => String::new(),
             InputState::Composing { .. } => {
-                let (reading, text) = self.resolve_composing_commit();
-                self.record_learning(&reading, &text);
+                // Not learned: nobody chose this text (see `commit_composing`).
+                let (_, text) = self.resolve_composing_commit();
                 self.end_composition();
                 text
             }
diff --git a/karukan-im/core/src/core/engine/mode.rs b/karukan-im/core/src/core/engine/mode.rs
index f9bade7..9739eb6 100644
--- a/karukan-im/core/src/core/engine/mode.rs
+++ b/karukan-im/core/src/core/engine/mode.rs
@@ -84,4 +84,91 @@ impl InputMethodEngine {
         };
         EngineResult::consumed().with_action(EngineAction::UpdateAuxText(aux))
     }
+
+    /// 無変換 — mozc's "SwitchKanaType" (MS-IME keymap). From the
+    /// composition it converts and selects the full-width katakana form;
+    /// during a conversion it cycles ひらがな → カタカナ → ﾊﾝｶｸ → ひらがな,
+    /// a non-kana selection (kanji) going to ひらがな. The candidate window
+    /// stays closed, as in MS-IME; Space reopens it, Enter or typing commits.
+    /// `None` when there is nothing to switch (Empty state, emoji queries).
+    pub(super) fn switch_kana_type(&mut self) -> Option<EngineResult> {
+        if self.mode.current() == InputMode::Emoji {
+            return None;
+        }
+        let form = match &self.state {
+            InputState::Empty => return None,
+            InputState::Composing { .. } => {
+                let result = self.start_conversion(LearningLookup::Use);
+                if !matches!(self.state, InputState::Conversion { .. }) {
+                    return Some(result);
+                }
+                KanaForm::Katakana
+            }
+            InputState::Conversion {
+                reading,
+                candidates,
+                ..
+            } => {
+                let selected = candidates.selected_text().unwrap_or_default();
+                if selected == KanaForm::Hiragana.render(reading) {
+                    KanaForm::Katakana
+                } else if selected == KanaForm::Katakana.render(reading) {
+                    KanaForm::HalfKatakana
+                } else {
+                    KanaForm::Hiragana
+                }
+            }
+        };
+        Some(self.focus_kana_form(form))
+    }
+
+    /// Select the `form` rendering of the conversion reading, adding it to
+    /// the candidate list when the list does not offer it.
+    fn focus_kana_form(&mut self, form: KanaForm) -> EngineResult {
+        let InputState::Conversion {
+            preedit,
+            candidates,
+            reading,
+            ..
+        } = &mut self.state
+        else {
+            return EngineResult::consumed();
+        };
+        let text = form.render(reading);
+        let index = match candidates.candidates().iter().position(|c| c.text == text) {
+            Some(index) => index,
+            None => {
+                let mut candidate = Candidate::with_reading(text.clone(), reading.clone());
+                candidate.source = Some(CandidateSource::Fallback);
+                candidates.push(candidate);
+                candidates.len() - 1
+            }
+        };
+        candidates.set_cursor(index);
+        *preedit = Preedit::with_text_highlighted(&text);
+        EngineResult::consumed()
+            .with_action(EngineAction::UpdatePreedit(preedit.clone()))
+            .with_action(EngineAction::HideCandidates)
+            .with_action(EngineAction::HideAuxText)
+    }
+}
+
+/// The kana renderings 無変換 cycles through.
+#[derive(Debug, Clone, Copy, PartialEq, Eq)]
+enum KanaForm {
+    Hiragana,
+    Katakana,
+    HalfKatakana,
+}
+
+impl KanaForm {
+    fn render(self, reading: &str) -> String {
+        match self {
+            KanaForm::Hiragana => reading.to_string(),
+            KanaForm::Katakana => karukan_engine::hiragana_to_katakana(reading),
+            KanaForm::HalfKatakana => karukan_engine::kana::katakana_to_half_width(
+                &karukan_engine::hiragana_to_katakana(reading),
+            ),
+        }
+    }
 }
diff --git a/karukan-im/core/src/core/engine/model.rs b/karukan-im/core/src/core/engine/model.rs
index f42c7b7..e4e32cb 100644
--- a/karukan-im/core/src/core/engine/model.rs
+++ b/karukan-im/core/src/core/engine/model.rs
@@ -348,6 +348,21 @@ impl InputMethodEngine {
     /// the cost stays bounded however long the reading grows. An empty
     /// result means "the model produced nothing"; a candidate equal to the
     /// reading is a real answer (kana-only words convert to themselves).
+    /// How Space splits `reading` for the model: the text already converted
+    /// on the chunk grid before the beamed span, the span's reading (empty
+    /// when the reading ends outside Japanese) and the span's left context.
+    /// Live conversion converts that same span with that same context, so
+    /// what is preferred for it (see `prefer`) agrees between the two.
+    pub(super) fn span_parts(&mut self, reading: &str) -> (String, String, String) {
+        let base_ctx = self.truncate_context_for_api();
+        let chars: Vec<char> = reading.chars().collect();
+        let span_start = self.beam_span_start(&chars);
+        let prefix = self.convert_on_chunk_grid(&chars[..span_start], &base_ctx);
+        let span: String = chars[span_start..].iter().collect();
+        let lctx = self.lctx_for(&base_ctx, &prefix);
+        (prefix, span, lctx)
+    }
+
     pub(super) fn model_candidates(&mut self, reading: &str, num_candidates: usize) -> Vec<String> {
         if !karukan_engine::contains_kana(reading) {
             return Vec::new();
diff --git a/karukan-im/core/src/core/engine/prefer.rs b/karukan-im/core/src/core/engine/prefer.rs
new file mode 100644
index 0000000..505a9c8
--- /dev/null
+++ b/karukan-im/core/src/core/engine/prefer.rs
@@ -0,0 +1,1795 @@
+//! What the user prefers, judged in context.
+//!
+//! Learning records what was chosen for a reading, never where: さい → 再
+//! says nothing about 「18さい」. Putting the learned surface first no
+//! matter what makes it wrong exactly where the text around it decides
+//! the word, and leaving it out of live conversion makes it useless while
+//! typing. Here the model is asked to judge: its log-probability for the
+//! learned surface and for its own answer, once with the text on the left
+//! and once without. Learning is the preference *without* context, so it
+//! wins unless the context itself argues against it — unless the model's
+//! margin for its own answer grows by more than a threshold once the
+//! context is there (18|さい: 再 loses 3 nats to 才; 今日は|みみ: ミミ loses
+//! nothing).
+//!
+//! The same judgement puts a learned word inside a sentence
+//! (耳が好きです → ミミが好きです) when the sentence's word lines up with
+//! the reading, stands on its own, and is one of the dictionary's
+//! spellings for it. After a number, the user dictionaries' counter
+//! entries (`〈数〉さい` → 歳) are preferred over the model's 才.
+//!
+//! Live conversion and Space both go through here, so what is shown while
+//! typing is what Space puts first.
+
+use std::collections::HashMap;
+
+use super::*;
+
+/// Largest growth of the model's margin against a learned surface that
+/// still counts as "the context does not object": for a whole reading,
+/// and for one word inside a sentence (where a name in katakana is
+/// always a little less expected than a common noun).
+const CONTEXT_SHIFT_MAX: f32 = 2.0;
+const SENTENCE_SHIFT_MAX: f32 = 3.0;
+/// Whatever the growth, a learned surface this far behind the model's own
+/// answer in context is not what was meant. (A persona that pushes the
+/// model towards kanji widens the margin even without context, which
+/// makes the growth alone look small.)
+const CONTEXT_GAP_MAX: f32 = 5.5;
+/// How far the learned spelling of a word the model left in hiragana may
+/// fall behind the model's sentence (くだ再ね for くださいね is far beyond it).
+const KANA_GAP_MAX: f32 = 4.0;
+/// A beam or a respelling of one word this far behind the model's best
+/// sentence is not offered at all.
+pub(super) const SWAP_GAP_MAX: f32 = 7.0;
+/// Learned surfaces judged per reading.
+const MAX_LEARNED_JUDGED: usize = 3;
+/// Learned words tried, and replaced, inside one sentence.
+const MAX_WORDS_TRIED: usize = 4;
+const MAX_WORDS_REPLACED: usize = 2;
+/// Reading length of a learned word looked for inside a sentence.
+const MIN_INNER_WORD_CHARS: usize = 2;
+const MAX_INNER_WORD_CHARS: usize = 12;
+/// Reading chars one kanji may stand for when aligning (承る = うけたまわ).
+const MAX_KANJI_READING_CHARS: usize = 8;
+/// Word alternatives (`word_alternatives`): reading length of a word,
+/// spellings taken per word and dictionary, and sentences offered in all.
+const MAX_ALTERNATIVE_WORD_CHARS: usize = 8;
+const ALTERNATIVES_PER_WORD: usize = 24;
+const MAX_ALTERNATIVES: usize = 48;
+/// A respelling of a word the model itself wrote as a word (花に → 鼻に)
+/// is a real homophone: kept much further down than a beam or a guess at
+/// a word in a run of hiragana (`SWAP_GAP_MAX`).
+pub(super) const WORD_GAP_MAX: f32 = 14.0;
+/// Word frequency (`order_by_model`): the dictionary cost a word is given
+/// at most, the cost of the bare kana when the dictionary has no entry
+/// for it, and the lead a more common word needs over the model's answer.
+pub(super) const MAX_WORD_COST: f32 = 9000.0;
+pub(super) const KANA_WORD_COST: f32 = 6000.0;
+pub(super) const PRIOR_MARGIN: f32 = 0.1;
+/// What the unconverted kana loses (nats) when a kanji word is the
+/// commoner spelling of a bare reading.
+pub(super) const KANA_BIAS: f32 = 3.5;
+/// A kanji word counts as the commoner spelling up to this much above the
+/// kana's own cost: わたし (0) and 私 (263) are as good as tied.
+pub(super) const NEAR_TIE_COST: f32 = 300.0;
+/// Common kanji spellings (`common_kanji`). A word the model left in
+/// hiragana gives way to a kanji spelling when the frequency data has
+/// that spelling as a frequent word about as common as the kana (いろんな
+/// 1603, 色んな 1817), the word is long enough to be no particle or
+/// formal noun (もの, こと, ため), the model does not mind the kanji for
+/// the bare word, and the sentence does not fall this far behind. For the
+/// very commonest words (私 263) the frequency data alone is trusted, and
+/// further (わたしは学生です is 3.5 ahead of 私は学生です).
+const MIN_COMMON_WORD_CHARS: usize = 3;
+const COMMON_WORD_COST: f32 = 2500.0;
+const BARE_KANJI_GAP: f32 = 0.75;
+const COMMON_KANJI_MARGIN: f32 = 2.5;
+const TOP_WORD_COST: f32 = 500.0;
+const TOP_KANJI_MARGIN: f32 = 4.0;
+/// Dictionary scores from here up are ranks, not frequency costs.
+pub(super) const UNKNOWN_WORD_COST: f32 = 20000.0;
+/// こそあど words and the question words written like them. Their kanji
+/// (何処, 其れ, 此の, 何故) are in the frequency data as if they were as
+/// common as the kana, which they are not: the kana stays unless chosen.
+const KOSOADO: &[&str] = &[
+    "これ",
+    "それ",
+    "あれ",
+    "どれ",
+    "ここ",
+    "そこ",
+    "あそこ",
+    "どこ",
+    "こちら",
+    "そちら",
+    "あちら",
+    "どちら",
+    "こっち",
+    "そっち",
+    "あっち",
+    "どっち",
+    "この",
+    "その",
+    "あの",
+    "どの",
+    "こう",
+    "そう",
+    "ああ",
+    "どう",
+    "こんな",
+    "そんな",
+    "あんな",
+    "どんな",
+    "いつ",
+    "なぜ",
+    "どなた",
+    "いずれ",
+    "いくつ",
+    "いくら",
+    "どうして",
+    "どうも",
+    "どうぞ",
+    "これら",
+    "それら",
+    "ここら",
+    "そこら",
+    "どこか",
+    "いつか",
+    "なにか",
+    "だれか",
+    "いつも",
+    "どこも",
+];
+
+/// The system dictionary lists kana that is a function word — a particle,
+/// an auxiliary, a formal noun (から, ます, こと) — under this mark and the
+/// kana. Their homophones' costs say nothing about how the kana is used.
+pub(super) const KANA_MARK: &str = "〈仮名〉";
+/// The mark conjugated forms are listed under (see `inflections`).
+pub(super) const INFLECTION_MARK: &str = "〈活〉";
+/// A commoner homophone (`may_lead`): where the model can hardly tell two
+/// spellings apart (within `TIE_MARGIN`), a word this much cheaper in the
+/// frequency data — some fifty times as frequent — leads
+/// (返還制度が悪い → 変換精度が悪い).
+const COMMONER_COST_GAIN: f32 = 2000.0;
+const TIE_MARGIN: f32 = 1.0;
+/// Compounds (`compound_alternatives`): kanji in a run taken for two
+/// dictionary words, the dearest word tried as a part, the pairs offered
+/// per compound, and the runs and reading length looked at.
+const COMPOUND_KANJI: std::ops::RangeInclusive<usize> = 4..=6;
+const COMPOUND_PART_COST: f32 = 6500.0;
+const COMPOUND_PAIRS: usize = 6;
+const MAX_COMPOUND_RUNS: usize = 3;
+const MAX_COMPOUND_READING_CHARS: usize = 40;
+/// A kanji compound the model made up for a reading (螺旋岩) gives way to
+/// one a dictionary has under exactly that reading (螺旋丸) when the model
+/// itself keeps the dictionary's within this margin. Only for readings
+/// this long: short ones are too ambiguous for the dictionary to settle.
+pub(super) const ATTESTED_MARGIN: f32 = 3.5;
+pub(super) const MIN_ATTESTED_READING_CHARS: usize = 4;
+/// Dictionary words tried in place of an English answer (`japanese_instead`).
+const MAX_JAPANESE_INSTEAD: usize = 8;
+/// How much is scored for one Space: about this many characters of
+/// alternatives in all, so a short reading gets up to `MAX_SCORED` of
+/// them and a 60-character one `MIN_SCORED`.
+pub(super) const SCORE_BUDGET_CHARS: usize = 1200;
+pub(super) const MIN_SCORED: usize = 16;
+pub(super) const MAX_SCORED: usize = 96;
+/// Characters of the user's own words that make the learned persona
+/// (`auto_persona`).
+const AUTO_PERSONA_CHARS: usize = 30;
+/// The persona's say (`persona_judge`): how many of the first answers it
+/// judges, how much it must move one towards the lead, how far ahead of
+/// the leader it must put it, and how far behind the leader that one may
+/// be without it.
+const PERSONA_JUDGED: usize = 8;
+/// Respellings of kana tried per keystroke in live conversion (`styled`).
+const MAX_STYLED: usize = 6;
+const PERSONA_GAIN: f32 = 4.0;
+const PERSONA_LEAD: f32 = 1.0;
+const PERSONA_PLAIN_MARGIN: f32 = 2.5;
+/// Another cut of the reading that holds a word the user chose before
+/// leads when the model keeps it within this of its best answer.
+pub(super) const LEARNED_RECUT_MARGIN: f32 = 4.0;
+/// A kanji spelling this much dearer than the kana is rare enough for
+/// `kanji_preference` to leave the kana alone (see `kana_usual`).
+const KANA_USUAL_COST: f32 = 1500.0;
+/// A respelling the model scores this much above its own first answer
+/// goes ahead of it.
+pub(super) const ADOPT_MARGIN: f32 = 1.0;
+/// Rounds of respelling the other words once one respelling was adopted.
+pub(super) const MAX_RESPELL_ROUNDS: usize = 2;
+/// Longest counter reading looked for at the start of a sentence.
+const MAX_COUNTER_CHARS: usize = 8;
+/// User-dictionary readings for counters after a number: `〈数〉さい`.
+pub(super) const NUMBER_MARK: &str = "〈数〉";
+/// Entries kept in the score cache before it is emptied.
+const SCORE_CACHE_CAPACITY: usize = 8192;
+
+/// Cache of model log-probabilities, keyed by the model, the reading, the
+/// left context fed to the model (persona included) and the surface.
+#[derive(Default)]
+pub(in crate::core) struct ScoreCache {
+    entries: HashMap<(ModelRole, String, String, String), f32>,
+}
+
+impl ScoreCache {
+    fn get(&self, model: ModelRole, reading: &str, lctx: &str, surface: &str) -> Option<f32> {
+        self.entries
+            .get(&(
+                model,
+                reading.to_string(),
+                lctx.to_string(),
+                surface.to_string(),
+            ))
+            .copied()
+    }
+
+    pub(in crate::core) fn insert(
+        &mut self,
+        model: ModelRole,
+        reading: &str,
+        lctx: &str,
+        surface: &str,
+        score: f32,
+    ) {
+        if self.entries.len() >= SCORE_CACHE_CAPACITY {
+            self.entries.clear();
+        }
+        self.entries.insert(
+            (
+                model,
+                reading.to_string(),
+                lctx.to_string(),
+                surface.to_string(),
+            ),
+            score,
+        );
+    }
+}
+
+/// How long the engine's own record of the text before the caret is
+/// trusted after the last key.
+const OWN_CONTEXT_TTL: std::time::Duration = std::time::Duration::from_secs(300);
+/// Characters of it kept.
+const OWN_CONTEXT_CHARS: usize = 80;
+
+/// The text the engine knows to be right before the caret because it put
+/// it there (see `InputMethodEngine::own_context`).
+#[derive(Default)]
+pub(in crate::core) struct OwnContext {
+    text: String,
+    at: Option<std::time::Instant>,
+}
+
+impl OwnContext {
+    pub(in crate::core) fn clear(&mut self) {
+        self.text.clear();
+        self.at = None;
+    }
+
+    /// The recorded text, unless it has gone stale.
+    pub(super) fn text(&self) -> &str {
+        match self.at {
+            Some(at) if at.elapsed() <= OWN_CONTEXT_TTL => &self.text,
+            _ => "",
+        }
+    }
+
+    fn push(&mut self, text: &str) {
+        if self.text().is_empty() {
+            self.text.clear();
+        }
+        // Context is the current line only, as with the editor's report.
+        match text.rsplit_once('\n') {
+            Some((_, after)) => {
+                self.text.clear();
+                self.text.push_str(after);
+            }
+            None => self.text.push_str(text),
+        }
+        self.text = keep_last_chars(&self.text, OWN_CONTEXT_CHARS);
+        self.at = Some(std::time::Instant::now());
+    }
+
+    /// Follow one key: committed text and characters let through to the
+    /// editor extend the record, Backspace shortens it, and any other key
+    /// the editor gets (Enter, arrows, Tab, a shortcut) may have moved
+    /// the caret or changed the text, so the record is dropped.
+    pub(in crate::core) fn follow(&mut self, key: &KeyEvent, result: &EngineResult) {
+        for action in &result.actions {
+            if let EngineAction::Commit(text) = action {
+                self.push(text);
+            }
+        }
+        if result.consumed || !key.is_press || key.keysym.is_modifier() {
+            return;
+        }
+        if key.keysym == Keysym::BACKSPACE && !key.modifiers.control_key {
+            self.text.pop();
+        } else if let Some(c) = key.to_char().filter(|_| key.is_printable_press()) {
+            self.push(&c.to_string());
+        } else {
+            self.clear();
+        }
+    }
+}
+
+/// One word of a sentence respelled (see `word_alternatives`).
+#[derive(Clone)]
+pub(super) struct WordAlternative {
+    /// The whole sentence with the word respelled.
+    pub text: String,
+    /// Whether the sentence had left the word in hiragana.
+    pub kana: bool,
+    /// The word's reading and its new spelling.
+    pub word: String,
+    pub surface: String,
+    /// The spelling's frequency cost when it is a frequent kanji word
+    /// about as common as the kana the sentence has (see `common_kanji`).
+    pub near_tie: Option<f32>,
+    /// How much cheaper the new spelling is than the one it replaces in
+    /// the frequency data (0 when the data does not have both).
+    pub gain: f32,
+    /// Whether the word is one that is as good as always left in kana
+    /// (ありがとう, ございます): `kanji_preference` leaves those alone.
+    pub kana_usual: bool,
+}
+
+/// A sentence with one word respelled (see `replace_aligned`).
+pub(super) struct Respelled {
+    pub text: String,
+    /// Whether the sentence had left the word in hiragana.
+    pub kana: bool,
+    /// How the sentence had spelled it.
+    pub was: String,
+}
+
+/// What a learned word inside a sentence leads to.
+#[derive(Default)]
+pub(super) struct SentenceLearning {
+    /// The sentence with the learned words the context accepts.
+    pub accepted: Option<String>,
+    /// Sentences with a learned word the context argues against: worth a
+    /// place in the list, not the first one.
+    pub alternatives: Vec<String>,
+}
+
+impl InputMethodEngine {
+    /// Brings `learned_persona` up to date with the learning record: the
+    /// words the user chose before, the most used and the latest (see
+    /// `LearningCache::persona_words`).
+    pub(super) fn refresh_persona(&mut self) {
+        if !self.config.auto_persona {
+            return;
+        }
+        let Some(cache) = &self.learning else {
+            return;
+        };
+        let revision = cache.revision();
+        if self.persona_revision == Some(revision) {
+            return;
+        }
+        self.persona_revision = Some(revision);
+        let words = cache.persona_words(AUTO_PERSONA_CHARS).join(" ");
+        self.learned_persona = karukan_engine::normalize_nfkc(&words);
+    }
+
+    /// Of `texts` (conversions of `reading` with nothing on its left, the
+    /// leader first), the one the user's own words speak for, if any.
+    ///
+    /// Read as text that came before, the learned persona tells the model
+    /// what this user writes about and how: after 出来る and 色んな, たぶん
+    /// is likelier 多分; after 銀行 and 残高, こうざ is 口座. So one choice
+    /// bears on every conversion after it, not only on its own reading.
+    /// But text that was never there also pulls at words it has nothing to
+    /// do with (黒き蝶 → 黒き調), so it does not write the sentence: it
+    /// only judges between answers the model came up with on its own, and
+    /// takes the lead from the first only for one that the persona makes
+    /// clearly likelier than the first (`PERSONA_LEAD`) and moves a long
+    /// way towards the lead (`PERSONA_GAIN`: what counts is what the
+    /// persona changes — a small move is as often chance as meaning), and
+    /// that was behind the first without it, but not far
+    /// (`PERSONA_PLAIN_MARGIN`; what the model scored above the first was
+    /// put behind it on purpose). With real text on the left the persona
+    /// has no say: that text is the better witness.
+    pub(super) fn persona_judge(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        texts: &[&str],
+        judge: ModelRole,
+    ) -> Option<String> {
+        // (Kana the other rules left as typed — これ, おはよう — is not the
+        // persona's to convert.)
+        if self.learned_persona.is_empty()
+            || !lctx.trim().is_empty()
+            || texts.len() < 2
+            || texts[0] == reading
+        {
+            return None;
+        }
+        let texts = &texts[..texts.len().min(PERSONA_JUDGED)];
+        let plain = self.model_scores_from(judge, reading, lctx, texts)?;
+        let persona = self.learned_persona.clone();
+        let with = self.model_scores_from(judge, reading, &persona, texts)?;
+        (1..texts.len())
+            .filter(|&at| {
+                let shift = (with[at] - with[0]) - (plain[at] - plain[0]);
+                shift >= PERSONA_GAIN
+                    && with[at] >= with[0] + PERSONA_LEAD
+                    && plain[at] <= plain[0]
+                    && plain[at] >= plain[0] - PERSONA_PLAIN_MARGIN
+            })
+            .max_by(|&a, &b| with[a].total_cmp(&with[b]))
+            .map(|at| texts[at].to_string())
+    }
+
+    /// The left context exactly as the model receives it (the persona is
+    /// prepended, as in `run_kana_kanji_conversion`).
+    fn scoring_lctx(&self, api_context: &str) -> String {
+        if self.config.persona.is_empty() {
+            api_context.to_string()
+        } else {
+            format!("{} {}", self.config.persona, api_context)
+        }
+    }
+
+    /// The model's log-probability of each of `surfaces` as the conversion
+    /// of `reading` after `api_context`. `None` when no model can say
+    /// (still loading, or the call failed) and the cache does not hold
+    /// them all.
+    pub(super) fn model_scores(
+        &mut self,
+        reading: &str,
+        api_context: &str,
+        surfaces: &[&str],
+    ) -> Option<Vec<f32>> {
+        self.model_scores_from(ModelRole::Main, reading, api_context, surfaces)
+    }
+
+    /// [`Self::model_scores`] from a given model. Live conversion on a
+    /// machine too slow for the main model judges its sentences with the
+    /// light one — the model that wrote them.
+    fn model_scores_from(
+        &mut self,
+        model: ModelRole,
+        reading: &str,
+        api_context: &str,
+        surfaces: &[&str],
+    ) -> Option<Vec<f32>> {
+        let lctx = self.scoring_lctx(api_context);
+        let missing: Vec<&str> = surfaces
+            .iter()
+            .copied()
+            .filter(|s| self.score_cache.get(model, reading, &lctx, s).is_none())
+            .collect();
+        if !missing.is_empty() {
+            // A model resting after it overran its time budget (see
+            // `guard`) is not asked to judge either.
+            if self.guard.is_resting(model, std::time::Instant::now()) {
+                return None;
+            }
+            let converter = match model {
+                ModelRole::Main => self.converters.kanji.as_ref(),
+                ModelRole::Light => self.converters.light_kanji.as_ref(),
+            }?;
+            let scores = converter.score(reading, &lctx, &missing).ok()?;
+            for (surface, score) in missing.iter().zip(scores) {
+                self.score_cache
+                    .insert(model, reading, &lctx, surface, score);
+            }
+        }
+        surfaces
+            .iter()
+            .map(|s| self.score_cache.get(model, reading, &lctx, s))
+            .collect()
+    }
+
+    /// The model's single best conversion of `reading` after `api_context`.
+    fn model_best(&mut self, reading: &str, api_context: &str) -> Option<String> {
+        self.run_kana_kanji_conversion(reading, api_context, 1, Budget::Space)
+            .into_iter()
+            .next()
+    }
+
+    /// Learned surfaces for exactly `reading`, best first.
+    fn learned_surfaces(&self, reading: &str) -> Vec<String> {
+        let Some(cache) = &self.learning else {
+            return Vec::new();
+        };
+        let drop_latin = !self.config.alphabet_candidates && conversion::has_kana(reading);
+        cache
+            .preferred(reading)
+            .into_iter()
+            .map(|(surface, _)| surface)
+            .filter(|s| !(drop_latin && conversion::is_latin_only(s)))
+            .take(MAX_LEARNED_JUDGED)
+            .collect()
+    }
+
+    /// The learned surface to use for `reading` after `lctx`, if the
+    /// context does not argue against it. `model_top` is the model's best
+    /// answer with that context when the caller already has it.
+    pub(super) fn learned_pick(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        model_top: Option<&str>,
+    ) -> Option<String> {
+        // What was chosen after a number before is the choice after this
+        // one: such choices are kept apart (`learning_key`), so 18歳 never
+        // changes a bare さい, nor the other way round.
+        if ends_with_digit(lctx)
+            && let Some(surface) = self
+                .learned_surfaces(&format!("{NUMBER_MARK}{reading}"))
+                .into_iter()
+                .next()
+        {
+            return Some(surface);
+        }
+        let learned = self.learned_surfaces(reading);
+        let first = learned.first()?.clone();
+        // No text on the left: the learned choice is all there is to go by.
+        if lctx.trim().is_empty() {
+            return Some(first);
+        }
+        let Some(top) = model_top
+            .map(str::to_string)
+            .or_else(|| self.model_best(reading, lctx))
+        else {
+            return Some(first);
+        };
+        if first == top {
+            return Some(first);
+        }
+        let Some(bare_top) = self.model_best(reading, "") else {
+            return Some(first);
+        };
+        let with_ctx: Vec<&str> = std::iter::once(top.as_str())
+            .chain(learned.iter().map(String::as_str))
+            .collect();
+        let bare: Vec<&str> = std::iter::once(bare_top.as_str())
+            .chain(learned.iter().map(String::as_str))
+            .collect();
+        let (Some(with_ctx), Some(bare)) = (
+            self.model_scores(reading, lctx, &with_ctx),
+            self.model_scores(reading, "", &bare),
+        ) else {
+            return Some(first);
+        };
+        learned
+            .iter()
+            .enumerate()
+            .find(|(i, surface)| {
+                let gap = with_ctx[0] - with_ctx[i + 1];
+                let shift = gap - (bare[0] - bare[i + 1]);
+                **surface == top || (shift <= CONTEXT_SHIFT_MAX && gap <= CONTEXT_GAP_MAX)
+            })
+            .map(|(_, surface)| surface.clone())
+    }
+
+    /// After a number, the user dictionaries' counter for `reading`
+    /// (`〈数〉さい` → 歳). Several entries (かい → 回, 階) are left to the
+    /// model to choose between.
+    pub(super) fn counter_pick(&mut self, reading: &str, lctx: &str) -> Option<String> {
+        if !ends_with_digit(lctx) {
+            return None;
+        }
+        let surfaces: Vec<String> = self
+            .dicts
+            .user
+            .as_ref()?
+            .exact_match_search(&format!("{NUMBER_MARK}{reading}"))?
+            .candidates
+            .iter()
+            .map(|c| c.surface.clone())
+            .collect();
+        let first = surfaces.first()?.clone();
+        if surfaces.len() == 1 {
+            return Some(first);
+        }
+        let refs: Vec<&str> = surfaces.iter().map(String::as_str).collect();
+        let Some(scores) = self.model_scores(reading, lctx, &refs) else {
+            return Some(first);
+        };
+        scores
+            .iter()
+            .enumerate()
+            .max_by(|a, b| a.1.total_cmp(b.1))
+            .map(|(i, _)| surfaces[i].clone())
+    }
+
+    /// The surface to put first for the whole of `reading` after `lctx`:
+    /// what was learned, when the context allows it, else a counter after
+    /// a number. `use_learning` is off for the learning-free conversion.
+    pub(super) fn preferred_surface(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        model_top: Option<&str>,
+        use_learning: bool,
+    ) -> Option<(String, CandidateSource)> {
+        if use_learning && let Some(surface) = self.learned_pick(reading, lctx, model_top) {
+            return Some((surface, CandidateSource::Learning));
+        }
+        self.counter_pick(reading, lctx)
+            .map(|surface| (surface, CandidateSource::UserDictionary))
+    }
+
+    /// A choice teaches the word, not only the phrase: when what was
+    /// picked for `reading` is the model's own sentence with one word
+    /// spelled another way (いろんな単語 → 色んな単語), that word is learned
+    /// too (いろんな → 色んな), and serves in every other sentence —
+    /// judged there by the context, like all learning.
+    pub(super) fn learn_word_choice(&mut self, reading: &str, chosen: &str) {
+        if self.learning.is_none() || conversion::is_character_query(reading) {
+            return;
+        }
+        let (prefix, span, lctx) = self.span_parts(reading);
+        let Some(chosen) = chosen.strip_prefix(prefix.as_str()) else {
+            return;
+        };
+        let Some(model) = self.model_best(&span, &lctx) else {
+            return;
+        };
+        // Another spelling of a word was put first unasked and the model's
+        // own was picked: that is the choice for the word.
+        let (_, respelled) = self.unasked_pick(&span, &lctx, model.clone(), ModelRole::Main);
+        if let Some(cache) = &mut self.learning {
+            for (word, surface) in respelled {
+                if chosen.contains(word.as_str()) && !chosen.contains(surface.as_str()) {
+                    cache.record_chosen(&word, &word);
+                }
+            }
+        }
+        if model == chosen {
+            return;
+        }
+        let picked = self
+            .word_alternatives(&span, &model, false)
+            .into_iter()
+            .find(|alternative| alternative.text == chosen);
+        if let (Some(picked), Some(cache)) = (&picked, &mut self.learning) {
+            cache.record_chosen(&picked.word, &picked.surface);
+        }
+        // Another cut of the reading was picked (ここで履物を脱ぐ): its
+        // words are the choice, each for its own reading.
+        if picked.is_none()
+            && let Some(recut) = self
+                .lattice_alternatives(&span, &model, true)
+                .into_iter()
+                .find(|recut| recut.text == chosen)
+            && let Some(cache) = &mut self.learning
+        {
+            for (word, surface) in &recut.words {
+                cache.record_chosen(word, surface);
+            }
+        }
+    }
+
+    /// Live conversion's text for one chunk: `model` (the model's
+    /// conversion of `reading` after `lctx`) unless something is preferred
+    /// — for the whole chunk, or for a learned word inside it.
+    pub(super) fn apply_preferences(&mut self, reading: &str, lctx: &str, model: String) -> String {
+        if conversion::is_character_query(reading) {
+            return model;
+        }
+        if let Some((surface, _)) = self.preferred_surface(reading, lctx, Some(&model), true) {
+            return surface;
+        }
+        // A bare word: the commoner dictionary word may lead, exactly as
+        // Space will have it (ぼく → 僕, わたし → 私).
+        if let Some(word) = self.bare_word_pick(reading, lctx, &model) {
+            return word;
+        }
+        // Judging a word inside a sentence is one more model pass per
+        // keystroke: where live conversion has fallen back to the light
+        // model for speed, the light model judges too.
+        let judge =
+            if self.metrics.adaptive_use_light_model && self.converters.light_kanji.is_some() {
+                ModelRole::Light
+            } else {
+                ModelRole::Main
+            };
+        let sentence = self
+            .respell_sentence(reading, lctx, &model, true, judge)
+            .accepted
+            .unwrap_or(model);
+        let sentence = self.unasked_pick(reading, lctx, sentence, judge).0;
+        self.styled(reading, lctx, sentence, judge)
+    }
+
+    /// `sentence` with a word it left in kana written in kanji, where
+    /// `kanji_preference` or the learned persona asks for it — what Space
+    /// would put first, so that live conversion shows the same. Only the
+    /// respellings of kana are tried here: scoring every homophone on
+    /// every keystroke would cost too much.
+    fn styled(&mut self, reading: &str, lctx: &str, sentence: String, judge: ModelRole) -> String {
+        let margin = self.config.kanji_preference;
+        if (margin <= 0.0 && self.learned_persona.is_empty())
+            || conversion::is_character_query(reading)
+        {
+            return sentence;
+        }
+        let mut current = sentence;
+        for _ in 0..MAX_RESPELL_ROUNDS {
+            let options: Vec<String> = self
+                .word_alternatives(reading, &current, true)
+                .into_iter()
+                .filter(|alternative| {
+                    alternative.kana
+                        && !alternative.kana_usual
+                        && kanji_count(&alternative.surface) > 0
+                })
+                .map(|alternative| alternative.text)
+                .take(MAX_STYLED)
+                .collect();
+            if options.is_empty() {
+                break;
+            }
+            let texts: Vec<&str> = std::iter::once(current.as_str())
+                .chain(options.iter().map(String::as_str))
+                .collect();
+            let Some(scores) = self.model_scores_from(judge, reading, lctx, &texts) else {
+                break;
+            };
+            let preferred = (1..texts.len())
+                .filter(|&at| margin > 0.0 && scores[at] >= scores[0] - margin)
+                .max_by(|&a, &b| scores[a].total_cmp(&scores[b]))
+                .map(|at| texts[at].to_string());
+            let Some(next) = preferred.or_else(|| self.persona_judge(reading, lctx, &texts, judge))
+            else {
+                break;
+            };
+            current = next;
+        }
+        current
+    }
+
+    /// What to show for a kana `reading` the model answered in English
+    /// (あっぷでーと → Update) when `alphabet_candidates` is off: the
+    /// katakana, the kana as typed, or a dictionary word for exactly this
+    /// reading — whichever the model finds likeliest. The kana as typed
+    /// when no model can say.
+    pub(super) fn japanese_instead(&mut self, reading: &str, lctx: &str) -> String {
+        let mut options = vec![
+            karukan_engine::hiragana_to_katakana(reading),
+            reading.to_string(),
+        ];
+        for dict in [self.dicts.user.as_deref(), self.dicts.system.as_deref()]
+            .into_iter()
+            .flatten()
+        {
+            if let Some(found) = dict.exact_match_search(reading) {
+                for candidate in found.candidates.iter().take(MAX_JAPANESE_INSTEAD) {
+                    let surface = &candidate.surface;
+                    if !conversion::is_unwanted_latin(reading, surface)
+                        && surface.chars().any(char::is_alphanumeric)
+                        && !options.contains(surface)
+                    {
+                        options.push(surface.clone());
+                    }
+                }
+            }
+        }
+        let texts: Vec<&str> = options.iter().map(String::as_str).collect();
+        let Some(scores) = self.model_scores(reading, lctx, &texts) else {
+            return reading.to_string();
+        };
+        let best = scores
+            .iter()
+            .enumerate()
+            .max_by(|a, b| a.1.total_cmp(b.1))
+            .map_or(1, |(at, _)| at);
+        options.swap_remove(best)
+    }
+
+    /// The system-dictionary word that should lead for a reading that is
+    /// one word with nothing on its left, when it beats `model` (see
+    /// `order_by_model`).
+    fn bare_word_pick(&mut self, reading: &str, lctx: &str, model: &str) -> Option<String> {
+        if !lctx.trim().is_empty() || self.config.word_prior <= 0.0 {
+            return None;
+        }
+        let drop_latin = !self.config.alphabet_candidates && conversion::has_kana(reading);
+        let exact: Vec<AnnotatedCandidate> = self
+            .dicts
+            .system
+            .as_ref()?
+            .exact_match_search(reading)?
+            .candidates
+            .iter()
+            .filter(|c| {
+                c.surface.chars().any(char::is_alphanumeric)
+                    && !(drop_latin && conversion::is_latin_only(&c.surface))
+            })
+            .map(|c| AnnotatedCandidate::new(c.surface.clone(), CandidateSource::Dictionary))
+            .collect();
+        let (ordered, ahead) = self.order_by_model(reading, lctx, exact, Some(model));
+        ahead
+            .then(|| ordered.into_iter().next().map(|c| c.text))
+            .flatten()
+    }
+
+    /// `sentence` (the model's conversion of `reading` after `lctx`) with
+    /// what is preferred inside it: a counter right after a number, then
+    /// learned words.
+    pub(super) fn respell_sentence(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        sentence: &str,
+        use_learning: bool,
+        judge: ModelRole,
+    ) -> SentenceLearning {
+        let counted = self.counter_in_sentence(reading, lctx, sentence);
+        let base = counted.as_deref().unwrap_or(sentence);
+        let mut result = if use_learning {
+            self.learned_in_sentence(reading, lctx, base, judge)
+        } else {
+            SentenceLearning::default()
+        };
+        if result.accepted.is_none() {
+            result.accepted = counted;
+        }
+        result
+    }
+
+    /// After a number, a counter that opens a longer reading
+    /// (18|さいのとき): the model's 才の時 becomes 歳の時. Only counters
+    /// with a single spelling, and only where the sentence's first word
+    /// is certain to be that counter (see `replace_aligned`).
+    fn counter_in_sentence(&self, reading: &str, lctx: &str, sentence: &str) -> Option<String> {
+        if !ends_with_digit(lctx) {
+            return None;
+        }
+        let user = self.dicts.user.as_ref()?;
+        let r: Vec<char> = reading.chars().collect();
+        for len in (1..r.len().min(MAX_COUNTER_CHARS + 1)).rev() {
+            let word: String = r[..len].iter().collect();
+            let Some(found) = user.exact_match_search(&format!("{NUMBER_MARK}{word}")) else {
+                continue;
+            };
+            let [counter] = found.candidates else {
+                continue;
+            };
+            if sentence.starts_with(counter.surface.as_str()) {
+                return None;
+            }
+            if let Some(respelled) =
+                self.replace_aligned(&r, 0..len, &counter.surface, sentence, true)
+            {
+                return Some(respelled.text);
+            }
+        }
+        None
+    }
+
+    /// Learned words inside `sentence`, the model's conversion of
+    /// `reading` after `lctx`. A word is replaced only when it is certain
+    /// which part of the sentence it is: the sentence spells it with one
+    /// of the dictionary's surfaces for that reading (or in katakana), the
+    /// text on both sides lines up with the rest of the reading, and the
+    /// word does not run on into a neighbour of the same script (最 in 最高
+    /// is not さい on its own). The `judge` model then decides as for a
+    /// whole reading.
+    fn learned_in_sentence(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        sentence: &str,
+        judge: ModelRole,
+    ) -> SentenceLearning {
+        let mut result = SentenceLearning::default();
+        let r: Vec<char> = reading.chars().collect();
+        if self.learning.is_none() || r.len() <= MIN_INNER_WORD_CHARS {
+            return result;
+        }
+
+        // Learned words whose reading occurs in the reading, strongest first.
+        let mut words: Vec<(usize, usize, String, f64)> = Vec::new();
+        if let Some(cache) = &self.learning {
+            for start in 0..r.len() {
+                let longest = MAX_INNER_WORD_CHARS.min(r.len() - start);
+                for len in MIN_INNER_WORD_CHARS..=longest {
+                    if len == r.len() {
+                        continue;
+                    }
+                    let word: String = r[start..start + len].iter().collect();
+                    if let Some((surface, score)) = cache.preferred(&word).into_iter().next() {
+                        words.push((start, len, surface, score));
+                    }
+                }
+            }
+        }
+        words.sort_by(|a, b| b.3.total_cmp(&a.3));
+        words.truncate(MAX_WORDS_TRIED);
+
+        let mut current = sentence.to_string();
+        let mut replaced = 0;
+        for (start, len, learned, _) in words {
+            if replaced >= MAX_WORDS_REPLACED {
+                break;
+            }
+            let word: String = r[start..start + len].iter().collect();
+            let Some(Respelled {
+                text: candidate,
+                kana,
+                ..
+            }) = self.replace_aligned(&r, start..start + len, &learned, &current, true)
+            else {
+                continue;
+            };
+            // A word the model left in hiragana (わたしは) has no rival
+            // spelling in the sentence: writing it the learned way (私は) is
+            // a matter of notation, judged by how far it falls behind alone.
+            if kana {
+                match self.model_scores_from(
+                    judge,
+                    reading,
+                    lctx,
+                    &[current.as_str(), candidate.as_str()],
+                ) {
+                    Some(scores) if scores[0] - scores[1] <= KANA_GAP_MAX => {
+                        current = candidate;
+                        replaced += 1;
+                    }
+                    _ => result.alternatives.push(candidate),
+                }
+                continue;
+            }
+            // Learning that only repeats the model's own default tells
+            // nothing the model did not weigh when it chose otherwise here.
+            let Some(bare_top) = self.model_best(&word, "") else {
+                result.alternatives.push(candidate);
+                continue;
+            };
+            if bare_top == learned {
+                continue;
+            }
+            let (Some(with_ctx), Some(bare)) = (
+                self.model_scores_from(
+                    judge,
+                    reading,
+                    lctx,
+                    &[current.as_str(), candidate.as_str()],
+                ),
+                self.model_scores_from(judge, &word, "", &[bare_top.as_str(), learned.as_str()]),
+            ) else {
+                result.alternatives.push(candidate);
+                continue;
+            };
+            let gap = with_ctx[0] - with_ctx[1];
+            let shift = gap - (bare[0] - bare[1]);
+            if shift <= SENTENCE_SHIFT_MAX && gap <= CONTEXT_GAP_MAX {
+                current = candidate;
+                replaced += 1;
+            } else {
+                result.alternatives.push(candidate);
+            }
+        }
+        if current != sentence {
+            result.accepted = Some(current);
+        }
+        result
+    }
+
+    /// Every sentence that respells one word of `sentence` (the model's
+    /// conversion of `reading`) the way a dictionary spells it. The
+    /// reading is gone through word by word — the longest dictionary word
+    /// at each position that can be located in the sentence for certain
+    /// (see `replace_aligned`) — and each word gets all its dictionary
+    /// spellings: はなに offers 鼻に, 華に, 洟に next to 花に. The second
+    /// field tells whether the sentence had left the word in hiragana.
+    /// The words share one budget, taken in turns, so a long sentence
+    /// still gets every word's first spellings. The model then ranks the
+    /// lot (`rank_by_model`).
+    pub(super) fn word_alternatives(
+        &self,
+        reading: &str,
+        sentence: &str,
+        skip_latin: bool,
+    ) -> Vec<WordAlternative> {
+        let r: Vec<char> = reading.chars().collect();
+        let mut words: Vec<Vec<WordAlternative>> = Vec::new();
+        let mut start = 0;
+        while start < r.len() {
+            let longest = MAX_ALTERNATIVE_WORD_CHARS.min(r.len() - start);
+            let mut advance = 1;
+            // Once a longer stretch of kana has been taken for a word, the
+            // shorter ones are only tried as conjugated forms.
+            let mut forms_only = false;
+            for len in (MIN_INNER_WORD_CHARS..=longest).rev() {
+                if len == r.len() {
+                    continue;
+                }
+                let word: String = r[start..start + len].iter().collect();
+                let mut surfaces: Vec<String> = Vec::new();
+                let dicts = if forms_only {
+                    [None, None]
+                } else {
+                    [self.dicts.user.as_deref(), self.dicts.system.as_deref()]
+                };
+                for dict in dicts.into_iter().flatten() {
+                    if let Some(found) = dict.exact_match_search(&word) {
+                        surfaces.extend(
+                            found
+                                .candidates
+                                .iter()
+                                .map(|c| c.surface.clone())
+                                .filter(|s| {
+                                    swap::is_word(s)
+                                        && !(skip_latin && conversion::is_latin_only(s))
+                                })
+                                .take(ALTERNATIVES_PER_WORD),
+                        );
+                    }
+                }
+                // Before more of the reading, the stretch may be a
+                // conjugated form (はなせ|ない).
+                if start + len < r.len() {
+                    for form in self.inflections(&word) {
+                        if !surfaces.contains(&form) {
+                            surfaces.push(form);
+                        }
+                    }
+                }
+                let mut texts: Vec<WordAlternative> = Vec::new();
+                for surface in surfaces {
+                    let Some(Respelled { text, kana, was }) =
+                        self.replace_aligned(&r, start..start + len, &surface, sentence, false)
+                    else {
+                        continue;
+                    };
+                    if texts.iter().any(|t| t.text == text) {
+                        continue;
+                    }
+                    // Proof of a word boundary is asked only where the
+                    // spelling may lead unasked.
+                    let near_tie =
+                        self.near_tie_cost(&word, &surface)
+                            .filter(|_| kana)
+                            .filter(|_| {
+                                self.replace_aligned(
+                                    &r,
+                                    start..start + len,
+                                    &surface,
+                                    sentence,
+                                    true,
+                                )
+                                .is_some_and(|strict| strict.text == text)
+                            });
+                    // A commoner homophone is one kanji word for another (返還 →
+                    // 変換): kana and katakana are notation, not homophones.
+                    let gain = match (self.word_cost(&word, &was), self.word_cost(&word, &surface))
+                    {
+                        (Some(old), Some(new))
+                            if kanji_count(&was) > 0 && kanji_count(&surface) > 0 =>
+                        {
+                            old - new
+                        }
+                        _ => 0.0,
+                    };
+                    let kana_usual = kana && self.kana_usual(&word, &surface);
+                    texts.push(WordAlternative {
+                        text,
+                        kana,
+                        word: word.clone(),
+                        surface,
+                        near_tie,
+                        gain,
+                        kana_usual,
+                    });
+                }
+                // The longest word here: shorter ones are parts of it.
+                // The search goes on behind it only when it is a word for
+                // certain. Kana that merely happens to read like one (は|で
+                // of それはできない as 派手) must not hide the word that
+                // begins inside it (できない).
+                if !texts.is_empty() {
+                    // Kana does not say which word it is: かいた may be the
+                    // place 頴田, and it may be 書い|た. The verb is looked
+                    // for inside it all the same.
+                    if texts.iter().all(|found| found.kana) && !forms_only {
+                        forms_only = true;
+                        // Kana that begins with a particle is likelier the
+                        // particle and another word (相談に|のった, not the
+                        // name にの): the word behind it is looked for too.
+                        let certain = !r[start..start + 1].iter().any(|c| PARTICLES.contains(c))
+                            && texts.iter().any(|found| {
+                                self.replace_aligned(
+                                    &r,
+                                    start..start + len,
+                                    &found.surface,
+                                    sentence,
+                                    true,
+                                )
+                                .is_some()
+                            });
+                        words.push(texts);
+                        if certain {
+                            advance = len;
+                        }
+                        continue;
+                    }
+                    if forms_only {
+                        words.push(texts);
+                        break;
+                    }
+                    let certain = texts.iter().any(|found| {
+                        !found.kana
+                            || self
+                                .replace_aligned(
+                                    &r,
+                                    start..start + len,
+                                    &found.surface,
+                                    sentence,
+                                    true,
+                                )
+                                .is_some()
+                    });
+                    words.push(texts);
+                    if certain {
+                        advance = len;
+                    }
+                    break;
+                }
+            }
+            start += advance;
+        }
+        words.extend(self.compound_alternatives(&r, sentence));
+        // A sentence reached both ways (the pair is itself a dictionary
+        // word) keeps what the pair knows about it.
+        let mut gains: HashMap<&str, f32> = HashMap::new();
+        for alternative in words.iter().flatten() {
+            let gain = gains.entry(alternative.text.as_str()).or_insert(0.0);
+            *gain = gain.max(alternative.gain);
+        }
+        let gains: HashMap<String, f32> = gains
+            .into_iter()
+            .map(|(text, gain)| (text.to_string(), gain))
+            .collect();
+        // In turns: every word's first spelling, then every word's second…
+        let mut out: Vec<WordAlternative> = Vec::new();
+        let longest = words.iter().map(Vec::len).max().unwrap_or(0);
+        for rank in 0..longest {
+            for word in &words {
+                if let Some(text) = word.get(rank)
+                    && !out.iter().any(|t| t.text == text.text)
+                {
+                    let mut alternative = text.clone();
+                    alternative.gain = gains.get(&text.text).copied().unwrap_or(text.gain);
+                    out.push(alternative);
+                    if out.len() >= MAX_ALTERNATIVES {
+                        return out;
+                    }
+                }
+            }
+        }
+        out
+    }
+
+    /// The conjugated forms of verbs and adjectives that read `word`
+    /// (はなせ: 話せ, 離せ, 放せ), commonest first. The system dictionary
+    /// lists them under a mark, apart from the words: 書い is nothing to
+    /// offer for かい, but inside かいて it is what 描い competes with.
+    pub(super) fn inflections(&self, word: &str) -> Vec<String> {
+        self.dicts
+            .system
+            .as_ref()
+            .and_then(|system| system.exact_match_search(&format!("{INFLECTION_MARK}{word}")))
+            .map(|found| {
+                found
+                    .candidates
+                    .iter()
+                    .take(ALTERNATIVES_PER_WORD)
+                    .map(|c| c.surface.clone())
+                    .collect()
+            })
+            .unwrap_or_default()
+    }
+
+    /// Whether `reading` is a word that stays in kana unless the user
+    /// chooses otherwise: a こそあど word, or kana the system dictionary
+    /// marks as a function word.
+    pub(super) fn stays_kana(&self, reading: &str) -> bool {
+        KOSOADO.contains(&reading)
+            || self.dicts.system.as_ref().is_some_and(|system| {
+                system
+                    .exact_match_search(&format!("{KANA_MARK}{reading}"))
+                    .is_some()
+            })
+    }
+
+    /// Whether `word` is as good as always left in kana rather than
+    /// written `surface`: a こそあど word, or one whose kana — as a word
+    /// or as a function word, whichever is commoner — the frequency data
+    /// has as far commoner than that spelling (ありがとう 646, 有難う 2392;
+    /// ございます 0, 御座います). (できる is a function word too, but
+    /// 出来る is not far behind it: that one is a matter of taste.)
+    pub(super) fn kana_usual(&self, word: &str, surface: &str) -> bool {
+        if KOSOADO.contains(&word) {
+            return true;
+        }
+        let function = self
+            .dicts
+            .system
+            .as_ref()
+            .and_then(|system| system.exact_match_search(&format!("{KANA_MARK}{word}")))
+            .and_then(|mark| mark.candidates.first().map(|c| c.score));
+        let kana = match (self.word_cost(word, word), function) {
+            (Some(a), Some(b)) => Some(a.min(b)),
+            (a, b) => a.or(b),
+        };
+        // The spelling as a word, or as a conjugated form (でき of できる:
+        // 出来 the noun is rare, 出来 of 出来る is not).
+        let form = self
+            .dicts
+            .system
+            .as_ref()
+            .and_then(|system| system.exact_match_search(&format!("{INFLECTION_MARK}{word}")))
+            .and_then(|forms| {
+                forms
+                    .candidates
+                    .iter()
+                    .find(|c| c.surface == surface)
+                    .map(|c| c.score)
+            });
+        let kanji = match (self.word_cost(word, surface), form) {
+            (Some(a), Some(b)) => Some(a.min(b)),
+            (a, b) => a.or(b),
+        };
+        match (kana, kanji) {
+            (Some(kana), Some(kanji)) => kanji > kana + KANA_USUAL_COST,
+            // A spelling the data does not have: rare for a function word
+            // (下さい), no evidence otherwise (出来るだけ is simply missing).
+            (Some(_), None) => function.is_some(),
+            _ => false,
+        }
+    }
+
+    /// The frequency cost of `surface` when it is a frequent kanji word
+    /// about as common as `word` left in kana.
+    fn near_tie_cost(&self, word: &str, surface: &str) -> Option<f32> {
+        if self.config.word_prior <= 0.0
+            || word.chars().count() < MIN_COMMON_WORD_CHARS
+            || kanji_count(surface) == 0
+            || self.stays_kana(word)
+        {
+            return None;
+        }
+        let (kana, kanji) = (self.word_cost(word, word)?, self.word_cost(word, surface)?);
+        (kanji <= kana + NEAR_TIE_COST && kanji <= COMMON_WORD_COST).then_some(kanji)
+    }
+
+    /// The frequency cost of `surface` as a spelling of `word`, where the
+    /// system dictionary carries one.
+    fn word_cost(&self, word: &str, surface: &str) -> Option<f32> {
+        if self.config.word_prior <= 0.0 {
+            return None;
+        }
+        self.dicts
+            .system
+            .as_ref()?
+            .exact_match_search(word)?
+            .candidates
+            .iter()
+            .find(|c| c.surface == surface)
+            .map(|c| c.score)
+            .filter(|cost| *cost < UNKNOWN_WORD_COST)
+    }
+
+    /// A run of kanji the model wrote as two dictionary words (返還|制度):
+    /// the other pairs of words with those two readings (変換|精度),
+    /// commonest pair first. One word of such a run cannot be told from
+    /// part of a longer word (see `stands_alone`), so the pair is
+    /// respelled as a whole — and two homophones that only make sense
+    /// together are found at all.
+    fn compound_alternatives(&self, r: &[char], sentence: &str) -> Vec<Vec<WordAlternative>> {
+        let mut out = Vec::new();
+        if self.config.word_prior <= 0.0 || r.len() > MAX_COMPOUND_READING_CHARS {
+            return out;
+        }
+        let Some(system) = self.dicts.system.as_ref() else {
+            return out;
+        };
+        // Kanji words for a reading with their costs, commonest first.
+        let words = |reading: &[char]| -> Vec<(String, f32)> {
+            let reading: String = reading.iter().collect();
+            let mut found: Vec<(String, f32)> = system
+                .exact_match_search(&reading)
+                .map(|found| {
+                    found
+                        .candidates
+                        .iter()
+                        .filter(|c| {
+                            c.score < UNKNOWN_WORD_COST
+                                && c.surface.chars().all(|ch| script(ch) == Script::Kanji)
+                        })
+                        .map(|c| (c.surface.clone(), c.score))
+                        .collect()
+                })
+                .unwrap_or_default();
+            found.sort_by(|a, b| a.1.total_cmp(&b.1));
+            found
+        };
+        let s: Vec<char> = sentence.chars().collect();
+        let mut runs = 0;
+        let mut from = 0;
+        while from < s.len() && runs < MAX_COMPOUND_RUNS {
+            if script(s[from]) != Script::Kanji {
+                from += 1;
+                continue;
+            }
+            let to = (from..s.len())
+                .find(|&i| script(s[i]) != Script::Kanji)
+                .unwrap_or(s.len());
+            let (run, before, after) = (&s[from..to], &s[..from], &s[to..]);
+            from = to;
+            if !COMPOUND_KANJI.contains(&run.len()) {
+                continue;
+            }
+            runs += 1;
+            // Where the run's reading can begin and end.
+            let starts: Vec<usize> = (before.len()..=r.len())
+                .filter(|&a| aligns(before, &r[..a]))
+                .take(2)
+                .collect();
+            let ends: Vec<usize> = (0..=r.len().saturating_sub(after.len()))
+                .rev()
+                .filter(|&b| aligns(after, &r[b..]))
+                .take(2)
+                .collect();
+            let mut pairs: Vec<WordAlternative> = Vec::new();
+            for &a in &starts {
+                for &b in &ends {
+                    if b < a + run.len() || b - a > MAX_ALTERNATIVE_WORD_CHARS * 2 {
+                        continue;
+                    }
+                    for cut in 2..=run.len() - 2 {
+                        let (first, second): (String, String) =
+                            (run[..cut].iter().collect(), run[cut..].iter().collect());
+                        for middle in a + 2..=b - 2 {
+                            let heads = words(&r[a..middle]);
+                            let Some(head_cost) = heads.iter().find(|w| w.0 == first).map(|w| w.1)
+                            else {
+                                continue;
+                            };
+                            let tails = words(&r[middle..b]);
+                            let Some(tail_cost) = tails.iter().find(|w| w.0 == second).map(|w| w.1)
+                            else {
+                                continue;
+                            };
+                            let was = head_cost + tail_cost;
+                            let mut found: Vec<(f32, String)> = Vec::new();
+                            for (head, head_cost) in &heads {
+                                for (tail, tail_cost) in &tails {
+                                    if head_cost.max(*tail_cost) <= COMPOUND_PART_COST
+                                        && (head != &first || tail != &second)
+                                    {
+                                        found
+                                            .push((head_cost + tail_cost, format!("{head}{tail}")));
+                                    }
+                                }
+                            }
+                            found.sort_by(|x, y| x.0.total_cmp(&y.0));
+                            for (cost, surface) in found.into_iter().take(COMPOUND_PAIRS) {
+                                let mut text: String = before.iter().collect();
+                                text.push_str(&surface);
+                                text.extend(after.iter());
+                                if !pairs.iter().any(|p| p.text == text) {
+                                    pairs.push(WordAlternative {
+                                        text,
+                                        kana: false,
+                                        word: r[a..b].iter().collect(),
+                                        surface,
+                                        near_tie: None,
+                                        gain: was - cost,
+                                        kana_usual: false,
+                                    });
+                                }
+                            }
+                        }
+                    }
+                }
+            }
+            if !pairs.is_empty() {
+                pairs.sort_by(|x, y| y.gain.total_cmp(&x.gain));
+                pairs.truncate(COMPOUND_PAIRS);
+                out.push(pairs);
+            }
+        }
+        out
+    }
+
+    /// Of `alternatives` (see `word_alternatives`), the sentences that may
+    /// take the lead unasked, with how far each may fall behind the
+    /// model's best and still do so: one that writes a word in its common
+    /// kanji spelling, and one with a much commoner homophone where the
+    /// model sees next to no difference. What the user has chosen for a
+    /// word — either way — is left to learning.
+    pub(super) fn may_lead(
+        &mut self,
+        alternatives: &[WordAlternative],
+        judge: ModelRole,
+    ) -> Vec<(WordAlternative, f32)> {
+        let mut out = Vec::new();
+        for alternative in alternatives {
+            if alternative.near_tie.is_none() && alternative.gain < COMMONER_COST_GAIN {
+                continue;
+            }
+            if self
+                .learning
+                .as_ref()
+                .is_some_and(|cache| !cache.preferred(&alternative.word).is_empty())
+            {
+                continue;
+            }
+            let margin = match alternative.near_tie {
+                None => TIE_MARGIN,
+                Some(cost) if cost <= TOP_WORD_COST => TOP_KANJI_MARGIN,
+                Some(_) => {
+                    let (word, surface) = (alternative.word.as_str(), alternative.surface.as_str());
+                    match self.model_scores_from(judge, word, "", &[word, surface]) {
+                        Some(bare) if bare[0] - bare[1] <= BARE_KANJI_GAP => COMMON_KANJI_MARGIN,
+                        _ => continue,
+                    }
+                }
+            };
+            out.push((alternative.clone(), margin));
+        }
+        out
+    }
+
+    /// `sentence` (a conversion of `reading` after `lctx`) with the words
+    /// that may lead unasked (see `may_lead`) respelled where the model
+    /// lets them (いろんな単語 → 色んな単語), and those words.
+    pub(super) fn unasked_pick(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        sentence: String,
+        judge: ModelRole,
+    ) -> (String, Vec<(String, String)>) {
+        let mut current = sentence;
+        let mut respelled = Vec::new();
+        let mut ceiling = f32::NEG_INFINITY;
+        if self.config.word_prior <= 0.0 || conversion::is_character_query(reading) {
+            return (current, respelled);
+        }
+        for _ in 0..MAX_RESPELL_ROUNDS {
+            let alternatives = self.word_alternatives(reading, &current, true);
+            let options = self.may_lead(&alternatives, judge);
+            if options.is_empty() {
+                break;
+            }
+            let texts: Vec<&str> = std::iter::once(current.as_str())
+                .chain(
+                    options
+                        .iter()
+                        .map(|(alternative, _)| alternative.text.as_str()),
+                )
+                .collect();
+            let Some(scores) = self.model_scores_from(judge, reading, lctx, &texts) else {
+                break;
+            };
+            ceiling = ceiling.max(scores[0]);
+            let Some(((alternative, _), _)) = options
+                .iter()
+                .zip(&scores[1..])
+                .filter(|((_, margin), score)| **score >= ceiling - margin)
+                .max_by(|a, b| a.1.total_cmp(b.1))
+            else {
+                break;
+            };
+            respelled.push((alternative.word.clone(), alternative.surface.clone()));
+            current = alternative.text.clone();
+        }
+        (current, respelled)
+    }
+
+    /// `sentence` with the word read `r[span]` respelled as `learned`, when
+    /// that word can be located for certain, and whether the sentence had
+    /// left it in hiragana. `strict` asks, for such a word, that a word can
+    /// begin there (see `starts_a_word`).
+    fn replace_aligned(
+        &self,
+        r: &[char],
+        span: std::ops::Range<usize>,
+        learned: &str,
+        sentence: &str,
+        strict: bool,
+    ) -> Option<Respelled> {
+        let word: String = r[span.clone()].iter().collect();
+        let word = word.as_str();
+        let katakana = karukan_engine::hiragana_to_katakana(word);
+        let mut spellings: Vec<String> = vec![katakana, word.to_string()];
+        for dict in [self.dicts.user.as_deref(), self.dicts.system.as_deref()]
+            .into_iter()
+            .flatten()
+        {
+            if let Some(found) = dict.exact_match_search(word) {
+                spellings.extend(found.candidates.iter().map(|c| c.surface.clone()));
+            }
+        }
+        // A conjugated form (離せ) stands in for another form of the same
+        // reading (話せ) or for the kana, never for a word (花背), and only
+        // where the conjugation goes on in hiragana (話せ|ない, not 買い|物).
+        let forms = if span.end < r.len() && !spellings.iter().any(|s| s == learned) {
+            self.inflections(word)
+        } else {
+            Vec::new()
+        };
+        let inflected = forms.iter().any(|form| form == learned);
+        if inflected {
+            spellings = forms;
+            spellings.push(word.to_string());
+        }
+        let s: Vec<char> = sentence.chars().collect();
+        let learned_chars: Vec<char> = learned.chars().collect();
+        // Longer spellings first: 砂狼シロコ before シロコ.
+        spellings.sort_by_key(|w| std::cmp::Reverse(w.chars().count()));
+        spellings.dedup();
+        for spelling in spellings {
+            let w: Vec<char> = spelling.chars().collect();
+            // Left in hiragana, the word is only where the reading says it
+            // is, and only where a word can begin (after わたしは, not
+            // inside ください).
+            let kana = w.iter().all(|&c| script(c) == Script::Hira);
+            if w.is_empty() || w.len() > s.len() || w == learned_chars || (kana && spelling != word)
+            {
+                continue;
+            }
+            for at in 0..=s.len().saturating_sub(w.len()) {
+                if s[at..at + w.len()] != w[..] {
+                    continue;
+                }
+                let (before, after) = (&s[..at], &s[at + w.len()..]);
+                let alone = if kana {
+                    // Listing alternatives (`strict` off) needs no proof of
+                    // a word boundary: the model's score sorts out まだ出来ない
+                    // from くだ再ね. Replacing on its own does.
+                    // (A conjugated form for kana always does: かい is
+                    // 書い only where a verb can begin, not in いつかいく.)
+                    (!strict && !inflected) || starts_a_word(before, &w, true)
+                } else {
+                    stands_alone(before, &w, after)
+                };
+                let goes_on =
+                    !inflected || after.first().is_some_and(|c| script(*c) == Script::Hira);
+                if alone
+                    && goes_on
+                    && aligns(before, &r[..span.start])
+                    && aligns(after, &r[span.end..])
+                {
+                    let mut text: String = before.iter().collect();
+                    text.push_str(learned);
+                    text.extend(after.iter());
+                    return Some(Respelled {
+                        text,
+                        kana,
+                        was: spelling,
+                    });
+                }
+            }
+        }
+        // Spelled as no dictionary has the word: a run of kanji that reads
+        // exactly as the word does is the word all the same (the model's
+        // 返還制度 for へんかんせいど, to be written 変換精度 as learned).
+        if learned.chars().all(|c| script(c) == Script::Kanji) {
+            let mut at = 0;
+            while at < s.len() {
+                if script(s[at]) != Script::Kanji {
+                    at += 1;
+                    continue;
+                }
+                let end = (at..s.len())
+                    .find(|&i| script(s[i]) != Script::Kanji)
+                    .unwrap_or(s.len());
+                let (before, run, after) = (&s[..at], &s[at..end], &s[end..]);
+                at = end;
+                if run.len() >= 2
+                    && run != &learned_chars[..]
+                    && aligns(run, &r[span.clone()])
+                    && aligns(before, &r[..span.start])
+                    && aligns(after, &r[span.end..])
+                {
+                    let mut text: String = before.iter().collect();
+                    text.push_str(learned);
+                    text.extend(after.iter());
+                    return Some(Respelled {
+                        text,
+                        kana: false,
+                        was: run.iter().collect(),
+                    });
+                }
+            }
+        }
+        None
+    }
+}
+
+/// Kanji in `text`: what the kanji preference compares.
+pub(super) fn kanji_count(text: &str) -> usize {
+    text.chars().filter(|&c| script(c) == Script::Kanji).count()
+}
+
+fn is_digit(c: char) -> bool {
+    c.is_ascii_digit() || ('０'..='９').contains(&c)
+}
+
+fn ends_with_digit(text: &str) -> bool {
+    text.chars().next_back().is_some_and(is_digit)
+}
+
+/// The key and surface a commit is learned under. A choice made right
+/// after a number is a counter (18歳, 3回): it is kept under
+/// `〈数〉` + reading, without the number, so it serves every number and
+/// leaves the bare reading alone.
+pub(super) fn learning_key(reading: &str, surface: &str, lctx: &str) -> (String, String) {
+    if let Some((digits, rest)) = split_number(reading)
+        && let Some(tail) = surface.strip_prefix(digits)
+        && !tail.is_empty()
+    {
+        return (format!("{NUMBER_MARK}{rest}"), tail.to_string());
+    }
+    if ends_with_digit(lctx) && !reading.starts_with(NUMBER_MARK) {
+        return (format!("{NUMBER_MARK}{reading}"), surface.to_string());
+    }
+    (reading.to_string(), surface.to_string())
+}
+
+/// The leading run of digits of `reading` and the rest, when both are
+/// there and the rest holds no further digit: 18さい → (18, さい).
+pub(super) fn split_number(reading: &str) -> Option<(&str, &str)> {
+    let end = reading
+        .char_indices()
+        .find(|&(_, c)| !is_digit(c))
+        .map(|(i, _)| i)?;
+    let (digits, rest) = reading.split_at(end);
+    (!digits.is_empty() && !rest.chars().any(is_digit)).then_some((digits, rest))
+}
+
+#[derive(Clone, Copy, PartialEq, Eq)]
+pub(super) enum Script {
+    Hira,
+    Kata,
+    Kanji,
+    Other,
+}
+
+pub(super) fn script(c: char) -> Script {
+    match c {
+        '\u{3041}'..='\u{309F}' => Script::Hira,
+        '\u{30A1}'..='\u{30FA}' | '\u{30FC}'..='\u{30FF}' | '\u{FF66}'..='\u{FF9F}' => Script::Kata,
+        '\u{4E00}'..='\u{9FFF}'
+        | '\u{3400}'..='\u{4DBF}'
+        | '\u{F900}'..='\u{FAFF}'
+        | '々'
+        | '〆' => Script::Kanji,
+        _ => Script::Other,
+    }
+}
+
+/// The one-letter particles a word may follow.
+const PARTICLES: &[char] = &['は', 'が', 'を', 'に', 'で', 'と', 'も', 'の', 'へ'];
+
+/// Whether a word spelled `w` can begin right after `before`: not in the
+/// middle of a kanji or katakana run (後|輩 is one word), and in hiragana
+/// only at the start or — with `after_particle` — after a particle
+/// (それで|わたしは, not くだ|さい). Word swaps do without the particles:
+/// で|きていない would let 着て in.
+pub(super) fn starts_a_word(before: &[char], w: &[char], after_particle: bool) -> bool {
+    let (Some(&prev), Some(&first)) = (before.last(), w.first()) else {
+        return true;
+    };
+    match (script(prev), script(first)) {
+        (Script::Kanji, Script::Kanji) | (Script::Kata, Script::Kata) => false,
+        (Script::Other, Script::Other) => !(prev.is_alphanumeric() && first.is_alphanumeric()),
+        (Script::Hira, Script::Hira) => after_particle && PARTICLES.contains(&prev),
+        _ => true,
+    }
+}
+
+/// Whether `w` is a word of its own between `before` and `after`: it must
+/// not continue a kanji or katakana run on either side (最|高, スーパー|マン),
+/// nor sit against letters or digits.
+fn stands_alone(before: &[char], w: &[char], after: &[char]) -> bool {
+    let joins = |a: char, b: char| match (script(a), script(b)) {
+        (Script::Kanji, Script::Kanji) | (Script::Kata, Script::Kata) => true,
+        (Script::Other, Script::Other) => a.is_alphanumeric() && b.is_alphanumeric(),
+        _ => false,
+    };
+    let left = before
+        .last()
+        .zip(w.first())
+        .is_some_and(|(&a, &b)| joins(a, b));
+    let right = w
+        .last()
+        .zip(after.first())
+        .is_some_and(|(&a, &b)| joins(a, b));
+    !left && !right
+}
+
+/// Whether `text` can be read as exactly `reading`: kana must match the
+/// reading letter for letter, a kanji stands for one or more reading
+/// chars, anything else matches itself or up to a few reading chars.
+pub(super) fn aligns(text: &[char], reading: &[char]) -> bool {
+    fn go(text: &[char], reading: &[char], memo: &mut HashMap<(usize, usize), bool>) -> bool {
+        let Some((&c, rest)) = text.split_first() else {
+            return reading.is_empty();
+        };
+        let key = (text.len(), reading.len());
+        if let Some(&known) = memo.get(&key) {
+            return known;
+        }
+        let kana = match script(c) {
+            Script::Hira => Some(c),
+            Script::Kata if c != 'ー' => karukan_engine::katakana_to_hiragana(&c.to_string())
+                .chars()
+                .next(),
+            Script::Kata => Some(c),
+            _ => None,
+        };
+        let ok = match kana {
+            Some(k) => reading.first() == Some(&k) && go(rest, &reading[1..], memo),
+            None => {
+                let literal = reading.first() == Some(&c) && go(rest, &reading[1..], memo);
+                let (min, max) = if script(c) == Script::Kanji {
+                    (1, MAX_KANJI_READING_CHARS)
+                } else {
+                    (0, 3)
+                };
+                literal || (min..=max.min(reading.len())).any(|n| go(rest, &reading[n..], memo))
+            }
+        };
+        memo.insert(key, ok);
+        ok
+    }
+    go(text, reading, &mut HashMap::new())
+}
+
+#[cfg(test)]
+mod tests {
+    use super::*;
+
+    fn chars(s: &str) -> Vec<char> {
+        s.chars().collect()
+    }
+
+    #[test]
+    fn alignment_follows_kana_and_lets_kanji_stretch() {
+        assert!(aligns(&chars("が好きです"), &chars("がすきです")));
+        assert!(aligns(&chars("その"), &chars("その")));
+        assert!(aligns(&chars("スーパー"), &chars("すーぱー")));
+        assert!(aligns(&chars(""), &chars("")));
+        assert!(!aligns(&chars("が好きです"), &chars("をすきです")));
+        assert!(!aligns(&chars("好"), &chars("")));
+        assert!(!aligns(&chars(""), &chars("す")));
+    }
+
+    #[test]
+    fn a_word_inside_a_compound_does_not_stand_alone() {
+        assert!(!stands_alone(&chars(""), &chars("最"), &chars("高")));
+        assert!(!stands_alone(&chars("再"), &chars("入学"), &chars("")));
+        assert!(!stands_alone(
+            &chars("スーパー"),
+            &chars("マン"),
+            &chars("")
+        ));
+        assert!(stands_alone(&chars(""), &chars("耳"), &chars("が好き")));
+        assert!(stands_alone(&chars("その"), &chars("際"), &chars("は")));
+        assert!(stands_alone(&chars("、"), &chars("耳"), &chars("。")));
+    }
+
+    #[test]
+    fn number_split() {
+        assert_eq!(split_number("18さい"), Some(("18", "さい")));
+        assert_eq!(split_number("１８さい"), Some(("１８", "さい")));
+        assert_eq!(split_number("さい"), None);
+        assert_eq!(split_number("18"), None);
+        assert_eq!(split_number("18さい2"), None);
+    }
+}
diff --git a/karukan-im/core/src/core/engine/swap.rs b/karukan-im/core/src/core/engine/swap.rs
new file mode 100644
index 0000000..f6c3bd1
--- /dev/null
+++ b/karukan-im/core/src/core/engine/swap.rs
@@ -0,0 +1,361 @@
+//! Word-swap candidates: dictionary alternatives for one word inside the
+//! model's sentence.
+//!
+//! The dictionaries are only ever looked up with the whole reading, so for
+//! a sentence like 「なになにのたびに」 they contribute nothing and the
+//! model's few beams are all there is: when none of them says 度に, no
+//! number of Space presses reaches it. Here the model's best sentence is
+//! aligned with the reading from the end — the hiragana they share is
+//! kept as-is — and the word right before that shared tail is looked up
+//! on its own. When the sentence spells that word with one of the
+//! dictionary's surfaces (or leaves it in kana), every other surface of
+//! the word yields a candidate: 何々の旅に → 何々の度に, 何々の足袋に, …;
+//! できていない → 出来ていない.
+
+use std::collections::{HashMap, HashSet};
+
+use super::*;
+
+/// Longest shared hiragana tail kept verbatim (okurigana and particles:
+/// に, ていない, …).
+const MAX_TAIL_CHARS: usize = 6;
+/// Word lengths tried before the tail. One-char readings are left out:
+/// they are mostly particles, and swapping those makes noise (旅に → 旅二).
+const MIN_WORD_CHARS: usize = 2;
+const MAX_WORD_CHARS: usize = 8;
+/// Surfaces taken per matched word, and candidates produced in total.
+const MAX_SURFACES_PER_WORD: usize = 6;
+const MAX_SWAPS: usize = 12;
+
+fn is_hiragana(c: char) -> bool {
+    matches!(c, '\u{3041}'..='\u{309F}' | 'ー')
+}
+
+impl InputMethodEngine {
+    /// Candidates made from `sentence` (the model's best conversion of
+    /// `reading`) by swapping one word for its other dictionary spellings.
+    /// The user dictionary is consulted before the system one.
+    pub(super) fn word_swap_candidates(
+        &self,
+        reading: &str,
+        sentence: &str,
+        skip_latin: bool,
+    ) -> Vec<String> {
+        let dicts: Vec<&Dictionary> = [self.dicts.user.as_deref(), self.dicts.system.as_deref()]
+            .into_iter()
+            .flatten()
+            .collect();
+        word_swaps(&dicts, reading, sentence, skip_latin)
+    }
+
+    /// The first of `exact` (system-dictionary candidates for exactly
+    /// `reading`) in the order of the model's score after `lctx` plus,
+    /// with `word_prior`, how common the dictionary says each word is —
+    /// its cost there is Mozc's, 500 per nat. The model alone is erratic
+    /// on a bare word (ぼく → 朴, きかん → 季刊): frequency steadies it. It
+    /// counts only while there is no text on the left for the model to go
+    /// by. The rest, and all of them when no model can say, keep the
+    /// dictionary's order.
+    ///
+    /// Also tells whether the first of them should go ahead of the
+    /// model's own answer `model_top`: when that answer is itself one of
+    /// these words (or the bare kana) and falls behind by `PRIOR_MARGIN`.
+    pub(super) fn order_by_model(
+        &mut self,
+        reading: &str,
+        lctx: &str,
+        mut exact: Vec<AnnotatedCandidate>,
+        model_top: Option<&str>,
+    ) -> (Vec<AnnotatedCandidate>, bool) {
+        const RANKED: usize = 24;
+        let head = exact.len().min(RANKED);
+        if head == 0 {
+            return (exact, false);
+        }
+        // With text on the left the model has what it needs: frequency
+        // would only pull 消化|きかん back from 器官 to 期間.
+        let weight = if lctx.trim().is_empty() {
+            self.config.word_prior
+        } else {
+            0.0
+        };
+        let costs: HashMap<String, f32> = self
+            .dicts
+            .system
+            .as_ref()
+            .and_then(|d| d.exact_match_search(reading))
+            .map(|found| {
+                found
+                    .candidates
+                    .iter()
+                    .map(|c| (c.surface.clone(), c.score))
+                    .collect()
+            })
+            .unwrap_or_default();
+        // Space asks for a conversion: where the dictionary knows a kanji
+        // word at least about as common as the bare kana (明日 for あした, 私
+        // for わたし), the kana gives way. Words normally left in kana keep
+        // their place: those whose kana is far commoner (ありがとう,
+        // よろしく), function words (から, ます, ない), こそあど words (どこ),
+        // and kana the data knows nothing about (して).
+        let known = |cost: f32| cost < prefer::UNKNOWN_WORD_COST;
+        let kana_cost = costs.get(reading).copied().filter(|cost| known(*cost));
+        let commoner_word = !self.stays_kana(reading)
+            && kana_cost.is_some_and(|kana_cost| {
+                costs.iter().any(|(surface, cost)| {
+                    *cost <= kana_cost + prefer::NEAR_TIE_COST && prefer::kanji_count(surface) > 0
+                })
+            });
+        let prior = |text: &str| -> Option<f32> {
+            let kana = text == reading || text == karukan_engine::hiragana_to_katakana(reading);
+            let cost = match costs.get(text).copied() {
+                Some(cost) if known(cost) => cost,
+                _ if text == reading => prefer::KANA_WORD_COST,
+                Some(cost) => cost,
+                None if kana => prefer::KANA_WORD_COST,
+                None => return None,
+            };
+            let bias = if text == reading && commoner_word && weight > 0.0 {
+                prefer::KANA_BIAS
+            } else {
+                0.0
+            };
+            Some(-weight * cost.min(prefer::MAX_WORD_COST) / 500.0 - bias)
+        };
+        let mut texts: Vec<String> = exact[..head].iter().map(|c| c.text.clone()).collect();
+        if let Some(top) = model_top
+            && !texts.iter().any(|t| t == top)
+        {
+            texts.push(top.to_string());
+        }
+        let refs: Vec<&str> = texts.iter().map(String::as_str).collect();
+        let Some(scores) = self.model_scores(reading, lctx, &refs) else {
+            return (exact, false);
+        };
+        let combined: HashMap<&str, f32> = refs
+            .iter()
+            .zip(&scores)
+            .map(|(text, score)| (*text, score + prior(text).unwrap_or(0.0)))
+            .collect();
+        let rest = exact.split_off(head);
+        exact.sort_by(|a, b| combined[b.text.as_str()].total_cmp(&combined[a.text.as_str()]));
+        let mut ahead = match (model_top, exact.first()) {
+            (Some(top), Some(first)) if first.text != top && weight > 0.0 => {
+                prior(top).is_some()
+                    && combined[first.text.as_str()] >= combined[top] + prefer::PRIOR_MARGIN
+            }
+            _ => false,
+        };
+        // A kanji compound no dictionary has under this reading (螺旋岩)
+        // against one the dictionary does have (螺旋丸): the dictionary's
+        // leads unless the model finds it far-fetched.
+        let all_kanji =
+            |text: &str| !text.is_empty() && prefer::kanji_count(text) == text.chars().count();
+        if !ahead
+            && let Some(top) = model_top
+            && prior(top).is_none()
+            && all_kanji(top)
+            && reading.chars().count() >= prefer::MIN_ATTESTED_READING_CHARS
+        {
+            let floor =
+                scores[refs.iter().position(|t| *t == top).unwrap_or(0)] - prefer::ATTESTED_MARGIN;
+            let raw: HashMap<&str, f32> =
+                refs.iter().copied().zip(scores.iter().copied()).collect();
+            if let Some(at) = exact
+                .iter()
+                .enumerate()
+                .filter(|(_, c)| all_kanji(&c.text) && raw[c.text.as_str()] >= floor)
+                .max_by(|a, b| raw[a.1.text.as_str()].total_cmp(&raw[b.1.text.as_str()]))
+                .map(|(at, _)| at)
+            {
+                let attested = exact.remove(at);
+                exact.insert(0, attested);
+                ahead = true;
+            }
+        }
+        // Kanji preference among the words: one that is written with more
+        // kanji than the leader and is not far behind it leads (わたし → 私).
+        let margin = self.config.kanji_preference;
+        let leader = match model_top {
+            Some(top) if !ahead => prior(top).map(|_| top.to_string()),
+            _ => exact.first().map(|c| c.text.clone()),
+        };
+        if margin > 0.0
+            && let Some(leader) = leader
+        {
+            let kanji = prefer::kanji_count(&leader);
+            let floor = combined[leader.as_str()] - margin;
+            // (Kana that is as good as always left so stays: そうする is
+            // not 奏する for anyone's taste.)
+            let from_kana = leader == reading;
+            let usual: Vec<bool> = exact
+                .iter()
+                .map(|c| from_kana && self.kana_usual(reading, &c.text))
+                .collect();
+            if let Some(at) = exact.iter().enumerate().position(|(at, c)| {
+                prefer::kanji_count(&c.text) > kanji
+                    && combined[c.text.as_str()] >= floor
+                    && !usual[at]
+            }) {
+                let chosen = exact.remove(at);
+                exact.insert(0, chosen);
+                ahead = true;
+            }
+        }
+        exact.extend(rest);
+        (exact, ahead)
+    }
+
+    /// `texts` — other conversions of the reading that `prefix` and
+    /// `span` make up — with the main model's score after `lctx`, best
+    /// first, and the score of `best` (the model's own first answer).
+    /// Those the model finds far-fetched next to `best` are dropped:
+    /// `loose` holds the texts that get the wider margin (dictionary
+    /// homophones of a word the model wrote). `None` when no model can
+    /// say.
+    pub(super) fn rank_by_model(
+        &mut self,
+        prefix: &str,
+        span: &str,
+        lctx: &str,
+        best: &str,
+        texts: Vec<String>,
+        loose: &HashSet<String>,
+    ) -> Option<(f32, Vec<(f32, String)>)> {
+        if texts.is_empty() || span.is_empty() {
+            return None;
+        }
+        let tails: Vec<&str> = std::iter::once(best)
+            .chain(texts.iter().map(String::as_str))
+            .map(|t| t.strip_prefix(prefix))
+            .collect::<Option<_>>()?;
+        let scores = self.model_scores(span, lctx, &tails)?;
+        let top = scores[0];
+        let mut ranked: Vec<(f32, String)> = scores[1..]
+            .iter()
+            .copied()
+            .zip(texts)
+            .filter(|(score, text)| {
+                let margin = if loose.contains(text) {
+                    prefer::WORD_GAP_MAX
+                } else {
+                    prefer::SWAP_GAP_MAX
+                };
+                *score >= top - margin
+            })
+            .collect();
+        ranked.sort_by(|a, b| b.0.total_cmp(&a.0));
+        Some((top, ranked))
+    }
+}
+
+/// The pure part of [`InputMethodEngine::word_swap_candidates`].
+pub(crate) fn word_swaps(
+    dicts: &[&Dictionary],
+    reading: &str,
+    sentence: &str,
+    skip_latin: bool,
+) -> Vec<String> {
+    let r: Vec<char> = reading.chars().collect();
+    let s: Vec<char> = sentence.chars().collect();
+    if dicts.is_empty() || r.len() < MIN_WORD_CHARS || s.is_empty() {
+        return Vec::new();
+    }
+
+    // How much hiragana the reading and the sentence end with in common.
+    let mut shared = 0;
+    while shared < r.len()
+        && shared < s.len()
+        && r[r.len() - 1 - shared] == s[s.len() - 1 - shared]
+        && is_hiragana(r[r.len() - 1 - shared])
+    {
+        shared += 1;
+    }
+
+    let mut out: Vec<String> = Vec::new();
+    // The longest kept tail first: it puts the swapped word right after
+    // the converted part (できて|いない → でき|ていない), where the model
+    // most often leaves a word in kana or picks the wrong homophone.
+    for tail_len in (0..=shared.min(MAX_TAIL_CHARS)).rev() {
+        let r_head = &r[..r.len() - tail_len];
+        let s_head = &s[..s.len() - tail_len];
+        let tail: String = r[r.len() - tail_len..].iter().collect();
+        let max_word = MAX_WORD_CHARS.min(r_head.len());
+        for word_len in (MIN_WORD_CHARS..=max_word).rev() {
+            let word: String = r_head[r_head.len() - word_len..].iter().collect();
+            for dict in dicts {
+                let Some(found) = dict.exact_match_search(&word) else {
+                    continue;
+                };
+                let surfaces: Vec<&str> = found
+                    .candidates
+                    .iter()
+                    .map(|c| c.surface.as_str())
+                    .collect();
+                // The spelling the sentence used for this word: one of the
+                // dictionary's, or the kana itself. The shortest match wins: a
+                // given-name entry may also hold the full name (シロコ, 砂狼シロコ),
+                // and only the short one lines up with the word.
+                let spelled = surfaces
+                    .iter()
+                    .copied()
+                    .chain(std::iter::once(word.as_str()))
+                    .filter(|m| !m.is_empty() && ends_with(s_head, m))
+                    .min_by_key(|m| m.chars().count());
+                let Some(spelled) = spelled else {
+                    continue;
+                };
+                let head_chars = &s_head[..s_head.len() - spelled.chars().count()];
+                // 輩 in 後輩 is not a word of its own: swapping it gives 後ハイ.
+                let spelled_chars: Vec<char> = spelled.chars().collect();
+                if !prefer::starts_a_word(head_chars, &spelled_chars, false) {
+                    continue;
+                }
+                let head: String = head_chars.iter().collect();
+                for surface in surfaces.iter().take(MAX_SURFACES_PER_WORD) {
+                    // mimiが好きです for みみがすきです: an English spelling of
+                    // one word is no better than of the whole reading.
+                    let latin = skip_latin && conversion::is_latin_only(surface);
+                    if *surface == spelled || latin || !is_word(surface) || overlaps(&head, surface)
+                    {
+                        continue;
+                    }
+                    let candidate = format!("{head}{surface}{tail}");
+                    if candidate != sentence && !out.contains(&candidate) {
+                        out.push(candidate);
+                        if out.len() >= MAX_SWAPS {
+                            return out;
+                        }
+                    }
+                }
+            }
+        }
+    }
+    out
+}
+
+/// Only plain words take part: entries like 「霊夢の天下とったるで!」 or
+/// 「円卓（円卓）」 are jokes and glosses, not spellings.
+pub(super) fn is_word(surface: &str) -> bool {
+    surface.chars().all(|c| {
+        matches!(c,
+            '\u{3041}'..='\u{309F}' | '\u{30A1}'..='\u{30FF}' | '\u{4E00}'..='\u{9FFF}'
+            | '\u{3400}'..='\u{4DBF}' | '々' | '〆'
+            | 'a'..='z' | 'A'..='Z' | '0'..='9' | 'ａ'..='ｚ' | 'Ａ'..='Ｚ' | '０'..='９')
+    })
+}
+
+/// A surface that repeats what the sentence already says right before it:
+/// a given-name entry spelled as the full name (しろこ → 砂狼シロコ) after
+/// the family name would read 砂狼砂狼シロコ.
+fn overlaps(head: &str, surface: &str) -> bool {
+    let head: Vec<char> = head.chars().collect();
+    let surface: Vec<char> = surface.chars().collect();
+    (2..=head.len().min(surface.len().saturating_sub(1)))
+        .any(|n| head[head.len() - n..] == surface[..n])
+}
+
+fn ends_with(text: &[char], suffix: &str) -> bool {
+    let suffix: Vec<char> = suffix.chars().collect();
+    suffix.len() <= text.len() && text[text.len() - suffix.len()..] == suffix[..]
+}
diff --git a/karukan-im/core/src/core/engine/tests/candidate_window.rs b/karukan-im/core/src/core/engine/tests/candidate_window.rs
index 4b3cf24..e4014e1 100644
--- a/karukan-im/core/src/core/engine/tests/candidate_window.rs
+++ b/karukan-im/core/src/core/engine/tests/candidate_window.rs
@@ -13,7 +13,7 @@ fn conversion_window_engine() -> InputMethodEngine {
         candidate_window: CandidateWindow::Conversion,
         ..EngineConfig::default()
     });
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(AI_DICT)));
+    engine.dicts.user = Some(dict_from_json(AI_DICT));
     engine
 }
 
@@ -135,7 +135,7 @@ fn test_emoji_picker_still_shows() {
 #[test]
 fn test_window_opens_while_typing_by_default() {
     let mut engine = make_live_conversion_engine();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(AI_DICT)));
+    engine.dicts.user = Some(dict_from_json(AI_DICT));
     engine.process_key(&press('a'));
     let result = engine.process_key(&press('i'));
     assert!(shows_candidates(&result), "{:?}", result.actions);
diff --git a/karukan-im/core/src/core/engine/tests/commit_on_input.rs b/karukan-im/core/src/core/engine/tests/commit_on_input.rs
new file mode 100644
index 0000000..1c4ceba
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/commit_on_input.rs
@@ -0,0 +1,173 @@
+//! `[conversion] commit_on_input`: a printable keystroke during an
+//! unfiltered conversion commits the selection and starts the next
+//! composition with it (MS-IME / mozc style).
+
+use super::*;
+
+/// Engine with `commit_on_input` on and a user dictionary entry
+/// あい → 藍, so the conversion's first candidate is deterministic.
+fn commit_on_input_engine() -> InputMethodEngine {
+    let mut engine = InputMethodEngine::with_config(EngineConfig {
+        commit_on_input: true,
+        ..EngineConfig::default()
+    });
+    engine.converters.kanji = None;
+    engine.dicts.user = Some(dict_from_json(
+        r#"[{"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}]"#,
+    ));
+    engine
+}
+
+/// Type あい and press Space.
+fn convert_ai(engine: &mut InputMethodEngine) {
+    engine.process_key(&press('a'));
+    engine.process_key(&press('i'));
+    engine.process_key(&press_key(Keysym::SPACE));
+    assert!(matches!(engine.state(), InputState::Conversion { .. }));
+    assert_eq!(engine.candidates().unwrap().selected_text(), Some("藍"));
+}
+
+fn committed(result: &EngineResult) -> Option<String> {
+    result.actions.iter().find_map(|a| match a {
+        EngineAction::Commit(text) => Some(text.clone()),
+        _ => None,
+    })
+}
+
+#[test]
+fn test_typing_commits_selection_and_starts_next_composition() {
+    let mut engine = commit_on_input_engine();
+    convert_ai(&mut engine);
+
+    let result = engine.process_key(&press('k'));
+    assert!(result.consumed);
+    assert_eq!(committed(&result).as_deref(), Some("藍"));
+    assert!(matches!(engine.state(), InputState::Composing { .. }));
+
+    // The keystroke opened the next composition: k + a → か.
+    engine.process_key(&press('a'));
+    assert_eq!(engine.input_buf.reading(), "か");
+    assert_eq!(engine.preedit().unwrap().text(), "か");
+
+    // Enter commits only the new composition.
+    let result = engine.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(committed(&result).as_deref(), Some("か"));
+}
+
+#[test]
+fn test_commit_precedes_the_new_preedit() {
+    // The frontend commits, resets the panel, then draws the new preedit,
+    // so Commit must come before UpdatePreedit in the same result.
+    let mut engine = commit_on_input_engine();
+    convert_ai(&mut engine);
+
+    let result = engine.process_key(&press('a'));
+    let commit_at = result
+        .actions
+        .iter()
+        .position(|a| matches!(a, EngineAction::Commit(_)))
+        .expect("commit action");
+    let preedit_at = result
+        .actions
+        .iter()
+        .rposition(|a| matches!(a, EngineAction::UpdatePreedit(_)))
+        .expect("preedit action");
+    assert!(commit_at < preedit_at);
+    assert_eq!(engine.preedit().unwrap().text(), "あ");
+}
+
+#[test]
+fn test_committed_text_is_learned() {
+    let mut engine = commit_on_input_engine();
+    engine.learning = Some(LearningCache::new(LearningConfig::default()));
+    convert_ai(&mut engine);
+    // Pick the second candidate so the record is not just the default.
+    engine.process_key(&press_key(Keysym::SPACE));
+    let picked = engine
+        .candidates()
+        .unwrap()
+        .selected_text()
+        .unwrap()
+        .to_string();
+
+    let result = engine.process_key(&press('k'));
+    assert_eq!(committed(&result).as_deref(), Some(picked.as_str()));
+    let learned = engine.learning.as_ref().unwrap().lookup("あい");
+    assert!(
+        learned.iter().any(|(surface, _)| surface == &picked),
+        "learned: {learned:?}"
+    );
+}
+
+#[test]
+fn test_digit_commits_and_starts_a_new_composition() {
+    let mut engine = commit_on_input_engine();
+    convert_ai(&mut engine);
+
+    let result = engine.process_key(&press('2'));
+    assert_eq!(committed(&result).as_deref(), Some("藍"));
+    assert_eq!(engine.input_buf.reading(), "2");
+}
+
+#[test]
+fn test_punctuation_commits_and_starts_a_new_composition() {
+    let mut engine = commit_on_input_engine();
+    convert_ai(&mut engine);
+
+    let result = engine.process_key(&press(','));
+    assert_eq!(committed(&result).as_deref(), Some("藍"));
+    assert_eq!(engine.preedit().unwrap().text(), "、");
+}
+
+#[test]
+fn test_shift_letter_commits_and_starts_direct_input() {
+    let mut engine = commit_on_input_engine();
+    convert_ai(&mut engine);
+
+    let result = engine.process_key(&press_shift('L'));
+    assert_eq!(committed(&result).as_deref(), Some("藍"));
+    assert!(engine.mode.current() == InputMode::Alphabet);
+    assert_eq!(engine.preedit().unwrap().text(), "L");
+}
+
+#[test]
+fn test_committed_text_becomes_left_context() {
+    let mut engine = commit_on_input_engine();
+    engine.set_surrounding_context("今日は", "");
+    convert_ai(&mut engine);
+
+    engine.process_key(&press('k'));
+    let left = engine
+        .surrounding_context
+        .as_ref()
+        .and_then(|c| c.left.clone());
+    assert_eq!(left.as_deref(), Some("今日は藍"));
+}
+
+#[test]
+fn test_filtered_view_still_refines() {
+    // Inside a narrowed source view typing is a search: it keeps refining.
+    let mut engine = commit_on_input_engine();
+    convert_ai(&mut engine);
+    engine.process_key(&press_ctrl(Keysym::KEY_I));
+    assert!(engine.state.filter().is_some());
+
+    let result = engine.process_key(&press('k'));
+    assert!(
+        committed(&result).is_none(),
+        "a filtered view must not commit"
+    );
+    assert!(matches!(engine.state(), InputState::Conversion { .. }));
+}
+
+#[test]
+fn test_off_keeps_refining() {
+    let mut engine = commit_on_input_engine();
+    engine.config.commit_on_input = false;
+    convert_ai(&mut engine);
+
+    let result = engine.process_key(&press('k'));
+    assert!(committed(&result).is_none());
+    engine.process_key(&press('a'));
+    assert_eq!(engine.input_buf.reading(), "あいか");
+}
diff --git a/karukan-im/core/src/core/engine/tests/conversion.rs b/karukan-im/core/src/core/engine/tests/conversion.rs
index 27d3a12..2d343ef 100644
--- a/karukan-im/core/src/core/engine/tests/conversion.rs
+++ b/karukan-im/core/src/core/engine/tests/conversion.rs
@@ -101,9 +101,9 @@ fn test_bare_digit_during_conversion_refines_instead_of_selecting() {
     // Digits are plain text input everywhere: during conversion they extend
     // the reading like any printable char, never select a candidate.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
@@ -118,12 +118,12 @@ fn test_bare_digit_during_conversion_refines_instead_of_selecting() {
 #[test]
 fn test_ctrl_digit_selects_candidate_during_conversion() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"あい","candidates":[
             {"surface":"藍","score":2.0},
             {"surface":"愛","score":1.0}
         ]}]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
@@ -148,9 +148,9 @@ fn test_ctrl_digit_selects_candidate_while_composing() {
     // commits straight from it — no Space needed first.
     let mut engine = InputMethodEngine::new();
     engine.converters.kanji = None;
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     let result = engine.process_key(&press('i'));
@@ -270,12 +270,12 @@ fn test_ctrl_b_in_conversion_moves_caret_like_left() {
 fn test_shift_space_steps_back_a_candidate() {
     // Shift+Space is prev-candidate, the mirror of Space, like Shift+Tab.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"あい","candidates":[
             {"surface":"藍","score":2.0},
             {"surface":"愛","score":1.0}
         ]}]"#,
-    )));
+    ));
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
     engine.process_key(&press_key(Keysym::SPACE));
diff --git a/karukan-im/core/src/core/engine/tests/exact_only.rs b/karukan-im/core/src/core/engine/tests/exact_only.rs
new file mode 100644
index 0000000..9fe46d1
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/exact_only.rs
@@ -0,0 +1,194 @@
+//! `prediction = false` and `alphabet_candidates = false`: only candidates
+//! whose reading is the typed one, and no Latin-only dictionary surfaces
+//! for a kana reading. ＠ lookups keep their English skill names.
+
+use super::*;
+
+fn engine(json: &str, prediction: bool, alphabet: bool) -> InputMethodEngine {
+    let mut engine = InputMethodEngine::new();
+    engine.converters.kanji = None;
+    engine.config.prediction = prediction;
+    engine.config.alphabet_candidates = alphabet;
+    engine.dicts.system = Some(dict_from_json(json));
+    engine
+}
+
+fn convert(engine: &mut InputMethodEngine, romaji: &str) -> Vec<String> {
+    for ch in romaji.chars() {
+        engine.process_key(&press(ch));
+    }
+    engine.process_key(&press_key(Keysym::SPACE));
+    engine
+        .candidates()
+        .unwrap()
+        .candidates()
+        .iter()
+        .map(|c| c.text.clone())
+        .collect()
+}
+
+const DICT: &str = r#"[
+    {"reading":"かい","candidates":[{"surface":"会","score":0.0},{"surface":"KAI","score":1.0},{"surface":"ｋａｉ","score":2.0},{"surface":"χ","score":3.0}]},
+    {"reading":"かいぎ","candidates":[{"surface":"会議","score":0.0}]},
+    {"reading":"＠しろこ","candidates":[{"surface":"砂狼シロコ","score":0.0},{"surface":"WHITE FANG 465","score":1.0}]}
+]"#;
+
+#[test]
+fn no_completion_of_a_longer_reading() {
+    let mut e = engine(DICT, false, true);
+    let list = convert(&mut e, "kai");
+    assert!(list.contains(&"会".to_string()), "{list:?}");
+    assert!(!list.contains(&"会議".to_string()), "{list:?}");
+}
+
+#[test]
+fn prediction_on_keeps_the_completion() {
+    let mut e = engine(DICT, true, true);
+    assert!(convert(&mut e, "kai").contains(&"会議".to_string()));
+}
+
+#[test]
+fn no_learned_completion_of_a_longer_reading() {
+    let mut e = engine(DICT, false, true);
+    e.learning = Some(karukan_engine::LearningCache::new(Default::default()));
+    e.learning.as_mut().unwrap().record("あわせて", "合わせて");
+    let list = convert(&mut e, "a");
+    assert!(!list.contains(&"合わせて".to_string()), "{list:?}");
+}
+
+#[test]
+fn no_latin_surface_for_a_kana_reading() {
+    let mut e = engine(DICT, false, false);
+    let list = convert(&mut e, "kai");
+    assert!(
+        !list.iter().any(|t| t == "KAI" || t == "ｋａｉ"),
+        "{list:?}"
+    );
+    assert!(
+        list.contains(&"χ".to_string()),
+        "Greek is not romaji: {list:?}"
+    );
+}
+
+#[test]
+fn latin_surfaces_stay_when_allowed() {
+    let mut e = engine(DICT, false, true);
+    assert!(convert(&mut e, "kai").contains(&"KAI".to_string()));
+}
+
+#[test]
+fn character_lookup_keeps_english_skills_and_order() {
+    let mut e = engine(DICT, false, false);
+    e.dicts.user = Some(dict_from_json(
+        r#"[{"reading":"＠しろこ","candidates":[{"surface":"砂狼シロコ","score":0.0},{"surface":"WHITE FANG 465","score":1.0}]}]"#,
+    ));
+    let list = convert(&mut e, "@siroko");
+    assert_eq!(list[0], "砂狼シロコ", "{list:?}");
+    assert!(list.contains(&"WHITE FANG 465".to_string()), "{list:?}");
+}
+
+#[test]
+fn latin_only_detection() {
+    use crate::core::engine::conversion::is_latin_only;
+    assert!(is_latin_only("KAI"));
+    assert!(is_latin_only("LuLu!!"));
+    assert!(is_latin_only("ｒｕｒｕ"));
+    assert!(is_latin_only("LU LU LU"));
+    assert!(!is_latin_only("χ"));
+    assert!(!is_latin_only("465"));
+    assert!(!is_latin_only("ルル"));
+    assert!(!is_latin_only("G戦杖"));
+}
+
+#[test]
+fn no_latin_word_swap_for_a_kana_reading() {
+    // The swap step rewrites one word of the model's sentence with its
+    // other dictionary spellings: るる → Lulu must not come back that way.
+    let json = r#"[{"reading":"るる","candidates":[{"surface":"縷々","score":0.0},{"surface":"Lulu","score":1.0}]}]"#;
+    let mut e = engine(json, false, false);
+    seed_model_cache(&mut e, "ルル", "", &["ルル"]);
+    let list = convert(&mut e, "ruru");
+    assert!(list.contains(&"縷々".to_string()), "{list:?}");
+    assert!(!list.contains(&"Lulu".to_string()), "{list:?}");
+}
+
+#[test]
+fn no_latin_model_sentence_for_a_kana_reading() {
+    let mut e = engine(
+        r#"[{"reading":"ん","candidates":[{"surface":"ン","score":0.0}]}]"#,
+        false,
+        false,
+    );
+    seed_model_cache(&mut e, "ルル", "", &["Lulu", "ルル"]);
+    let list = convert(&mut e, "ruru");
+    assert_eq!(list[0], "ルル", "{list:?}");
+    assert!(!list.contains(&"Lulu".to_string()), "{list:?}");
+}
+
+#[test]
+fn answered_character_lookup_skips_the_model() {
+    let mut e = engine(
+        r#"[{"reading":"ん","candidates":[{"surface":"ン","score":0.0}]}]"#,
+        false,
+        false,
+    );
+    e.dicts.user = Some(dict_from_json(
+        r#"[{"reading":"＠こいし","candidates":[{"surface":"古明地こいし","score":0.0}]}]"#,
+    ));
+    seed_model_cache(&mut e, "＠コイシ", "", &["＠小石"]);
+    let list = convert(&mut e, "@koisi");
+    assert_eq!(list[0], "古明地こいし", "{list:?}");
+    assert!(!list.contains(&"＠小石".to_string()), "{list:?}");
+}
+
+#[test]
+fn live_conversion_keeps_kana_instead_of_latin() {
+    let mut e = engine(
+        r#"[{"reading":"ん","candidates":[{"surface":"ン","score":0.0}]}]"#,
+        false,
+        false,
+    );
+    e.live.enabled = true;
+    seed_model_cache(&mut e, "ルル", "", &["lulu"]);
+    e.process_key(&press('r'));
+    e.process_key(&press('u'));
+    e.process_key(&press('r'));
+    e.process_key(&press('u'));
+    assert_eq!(e.chunks[0].converted, "るる");
+    assert_ne!(e.preedit().unwrap().text(), "lulu");
+}
+
+#[test]
+fn live_conversion_leaves_a_character_lookup_as_typed() {
+    let mut e = engine(
+        r#"[{"reading":"ん","candidates":[{"surface":"ン","score":0.0}]}]"#,
+        false,
+        false,
+    );
+    e.live.enabled = true;
+    seed_model_cache(&mut e, "＠コイシ", "", &["＠小石"]);
+    for ch in "@koisi".chars() {
+        e.process_key(&press(ch));
+    }
+    assert_eq!(e.preedit().unwrap().text(), "＠こいし");
+}
+
+#[test]
+fn no_romaji_fragment_in_a_kana_readings_model_answers() {
+    use crate::core::engine::conversion::has_romaji_fragment;
+    assert!(has_romaji_fragment("mimiが好きです"));
+    assert!(has_romaji_fragment("macoら"));
+    assert!(!has_romaji_fragment("Tシャツ"));
+    assert!(!has_romaji_fragment("USBメモリ"));
+    assert!(!has_romaji_fragment("iPhone"));
+    assert!(!has_romaji_fragment("耳が好きです"));
+
+    let mut e = engine(
+        r#"[{"reading":"ん","candidates":[{"surface":"ン","score":0.0}]}]"#,
+        false,
+        false,
+    );
+    seed_model_cache(&mut e, "マコラ", "", &["macoら", "まこら"]);
+    let list = convert(&mut e, "makora");
+    assert!(!list.contains(&"macoら".to_string()), "{list:?}");
+}
diff --git a/karukan-im/core/src/core/engine/tests/learning.rs b/karukan-im/core/src/core/engine/tests/learning.rs
index e2b0062..2a728f5 100644
--- a/karukan-im/core/src/core/engine/tests/learning.rs
+++ b/karukan-im/core/src/core/engine/tests/learning.rs
@@ -389,6 +389,30 @@ fn ctrl_delete_removes_prefix_matched_entry_by_full_reading() {
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
     engine.process_key(&press_key(Keysym::SPACE));
+    // A prefix match is a past, longer reading: it no longer takes the
+    // first slot, so walk down to it.
+    let first = engine
+        .state()
+        .candidates()
+        .unwrap()
+        .selected()
+        .unwrap()
+        .clone();
+    assert_ne!(first.text, "挨拶");
+    for _ in 0..20 {
+        if engine
+            .state()
+            .candidates()
+            .unwrap()
+            .selected()
+            .unwrap()
+            .text
+            == "挨拶"
+        {
+            break;
+        }
+        engine.process_key(&press_key(Keysym::SPACE));
+    }
 
     let selected = engine
         .state()
@@ -465,3 +489,19 @@ fn space_key_keeps_learning_in_composing() {
         texts,
     );
 }
+
+#[test]
+fn exact_learning_still_comes_first() {
+    let mut engine = engine_with_learned("あい", "藍");
+    engine.process_key(&press('a'));
+    engine.process_key(&press('i'));
+    engine.process_key(&press_key(Keysym::SPACE));
+    let first = engine
+        .state()
+        .candidates()
+        .unwrap()
+        .selected()
+        .unwrap()
+        .clone();
+    assert_eq!(first.text, "藍");
+}
diff --git a/karukan-im/core/src/core/engine/tests/mod.rs b/karukan-im/core/src/core/engine/tests/mod.rs
index 1d733fd..fa17682 100644
--- a/karukan-im/core/src/core/engine/tests/mod.rs
+++ b/karukan-im/core/src/core/engine/tests/mod.rs
@@ -10,25 +10,32 @@ mod basic;
 mod candidate_window;
 mod candidates;
 mod chunks;
+mod commit_on_input;
 mod conversion;
 mod cursor;
 mod date;
 mod emoji;
+mod exact_only;
 mod katakana;
 mod learning;
 mod live_conversion;
 mod mode_toggle;
+mod muhenkan;
 mod overload;
 mod passthrough;
 mod pending_romaji;
 mod persona;
 mod predictive;
+mod prefer;
 mod rewriter;
+mod shared_dicts;
 mod single_kanji;
 mod source_filter;
 mod strategy;
 mod surrounding;
+mod user_dict_order;
 mod width;
+mod word_swap;
 
 /// Engine seeded with a learning entry `reading → surface`, no kanji model.
 /// Bypasses `init.rs` (which gates learning on settings + file I/O) and
@@ -59,12 +66,12 @@ fn seed_model_cache(engine: &mut InputMethodEngine, katakana: &str, lctx: &str,
 }
 
 /// Build a dictionary from inline JSON, hiding the temp-file plumbing.
-fn dict_from_json(json: &str) -> Dictionary {
+fn dict_from_json(json: &str) -> std::sync::Arc<Dictionary> {
     use std::io::Write;
     let mut tmp = tempfile::NamedTempFile::new().unwrap();
     tmp.write_all(json.as_bytes()).unwrap();
     tmp.flush().unwrap();
-    Dictionary::build_from_json(tmp.path()).unwrap()
+    std::sync::Arc::new(Dictionary::build_from_json(tmp.path()).unwrap())
 }
 
 fn press(ch: char) -> KeyEvent {
diff --git a/karukan-im/core/src/core/engine/tests/muhenkan.rs b/karukan-im/core/src/core/engine/tests/muhenkan.rs
new file mode 100644
index 0000000..144408d
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/muhenkan.rs
@@ -0,0 +1,128 @@
+//! 無変換: mozc's "SwitchKanaType" (MS-IME keymap).
+
+use super::*;
+
+fn engine_with_ai() -> InputMethodEngine {
+    let mut engine = InputMethodEngine::new();
+    engine.converters.kanji = None;
+    engine.dicts.user = Some(dict_from_json(
+        r#"[{"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}]"#,
+    ));
+    engine.process_key(&press('a'));
+    engine.process_key(&press('i'));
+    engine
+}
+
+fn muhenkan(engine: &mut InputMethodEngine) -> EngineResult {
+    engine.process_key(&press_key(Keysym::MUHENKAN))
+}
+
+fn shown(engine: &InputMethodEngine) -> String {
+    engine.preedit().unwrap().text().to_string()
+}
+
+#[test]
+fn test_muhenkan_converts_the_composition_to_katakana() {
+    let mut engine = engine_with_ai();
+    let result = muhenkan(&mut engine);
+
+    assert!(result.consumed);
+    assert!(matches!(engine.state(), InputState::Conversion { .. }));
+    assert_eq!(shown(&engine), "アイ");
+    assert_eq!(engine.candidates().unwrap().selected_text(), Some("アイ"));
+    // MS-IME keeps the candidate window closed.
+    assert!(
+        result
+            .actions
+            .iter()
+            .any(|a| matches!(a, EngineAction::HideCandidates))
+    );
+    assert!(
+        !result
+            .actions
+            .iter()
+            .any(|a| matches!(a, EngineAction::Commit(_)))
+    );
+}
+
+#[test]
+fn test_muhenkan_cycles_katakana_half_hiragana() {
+    let mut engine = engine_with_ai();
+    muhenkan(&mut engine);
+    assert_eq!(shown(&engine), "アイ");
+    muhenkan(&mut engine);
+    assert_eq!(shown(&engine), "ｱｲ");
+    muhenkan(&mut engine);
+    assert_eq!(shown(&engine), "あい");
+    muhenkan(&mut engine);
+    assert_eq!(shown(&engine), "アイ");
+}
+
+#[test]
+fn test_muhenkan_from_a_kanji_selection_goes_to_hiragana() {
+    let mut engine = engine_with_ai();
+    engine.process_key(&press_key(Keysym::SPACE));
+    assert_eq!(engine.candidates().unwrap().selected_text(), Some("藍"));
+
+    muhenkan(&mut engine);
+    assert_eq!(shown(&engine), "あい");
+    muhenkan(&mut engine);
+    assert_eq!(shown(&engine), "アイ");
+}
+
+#[test]
+fn test_enter_commits_the_switched_kana() {
+    let mut engine = engine_with_ai();
+    muhenkan(&mut engine);
+    let result = engine.process_key(&press_key(Keysym::RETURN));
+    assert!(
+        result
+            .actions
+            .iter()
+            .any(|a| matches!(a, EngineAction::Commit(t) if t == "アイ"))
+    );
+    assert!(matches!(engine.state(), InputState::Empty));
+}
+
+#[test]
+fn test_typing_after_muhenkan_commits_with_commit_on_input() {
+    let mut engine = engine_with_ai();
+    engine.config.commit_on_input = true;
+    muhenkan(&mut engine);
+    let result = engine.process_key(&press('k'));
+    assert!(
+        result
+            .actions
+            .iter()
+            .any(|a| matches!(a, EngineAction::Commit(t) if t == "アイ"))
+    );
+    engine.process_key(&press('a'));
+    assert_eq!(shown(&engine), "か");
+}
+
+#[test]
+fn test_space_after_muhenkan_reopens_the_list() {
+    let mut engine = engine_with_ai();
+    muhenkan(&mut engine);
+    let result = engine.process_key(&press_key(Keysym::SPACE));
+    assert!(
+        result
+            .actions
+            .iter()
+            .any(|a| matches!(a, EngineAction::ShowCandidates(_)))
+    );
+}
+
+#[test]
+fn test_muhenkan_with_nothing_typed_passes_through() {
+    let mut engine = InputMethodEngine::new();
+    assert!(!muhenkan(&mut engine).consumed);
+}
+
+#[test]
+fn test_modified_muhenkan_is_not_hijacked() {
+    let mut engine = engine_with_ai();
+    let result = engine.process_key(&press_ctrl(Keysym::MUHENKAN));
+    assert!(!result.consumed);
+    assert!(matches!(engine.state(), InputState::Composing { .. }));
+}
diff --git a/karukan-im/core/src/core/engine/tests/overload.rs b/karukan-im/core/src/core/engine/tests/overload.rs
index c30869e..425cac9 100644
--- a/karukan-im/core/src/core/engine/tests/overload.rs
+++ b/karukan-im/core/src/core/engine/tests/overload.rs
@@ -84,9 +84,9 @@ fn a_resting_model_still_answers_from_the_cache() {
 #[test]
 fn the_dictionary_still_converts_while_the_model_rests() {
     let mut engine = live_engine();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[{"reading": "きょう", "candidates": [{"surface": "今日", "score": 100.0}]}]"#,
-    )));
+    ));
     rest_the_model(&mut engine);
     type_keys(&mut engine, "kyou");
     engine.process_key(&press_key(Keysym::SPACE));
diff --git a/karukan-im/core/src/core/engine/tests/predictive.rs b/karukan-im/core/src/core/engine/tests/predictive.rs
index a35dd43..2711655 100644
--- a/karukan-im/core/src/core/engine/tests/predictive.rs
+++ b/karukan-im/core/src/core/engine/tests/predictive.rs
@@ -5,9 +5,9 @@ use super::*;
 #[test]
 fn predictive_dict_candidates_carry_full_reading() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[{"reading":"わせだ","candidates":[{"surface":"早稲田","score":1000.0}]}]"#,
-    )));
+    ));
 
     let candidates = engine.lookup_dict_candidates("わせ");
     let waseda = candidates
@@ -20,9 +20,9 @@ fn predictive_dict_candidates_carry_full_reading() {
 #[test]
 fn predictive_needs_two_typed_chars() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[{"reading":"わせだ","candidates":[{"surface":"早稲田","score":1000.0}]}]"#,
-    )));
+    ));
 
     assert!(
         engine
@@ -35,12 +35,12 @@ fn predictive_needs_two_typed_chars() {
 #[test]
 fn exact_matches_stay_ahead_of_predictive() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[
             {"reading":"わせ","candidates":[{"surface":"和瀬","score":5000.0}]},
             {"reading":"わせだ","candidates":[{"surface":"早稲田","score":100.0}]}
         ]"#,
-    )));
+    ));
 
     let candidates = engine.lookup_dict_candidates("わせ");
     let texts: Vec<&str> = candidates.iter().map(|c| c.text.as_str()).collect();
@@ -55,12 +55,12 @@ fn exact_matches_stay_ahead_of_predictive() {
 #[test]
 fn pending_romaji_narrows_predictive_candidates() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[
             {"reading":"わせだ","candidates":[{"surface":"早稲田","score":1000.0}]},
             {"reading":"わせりん","candidates":[{"surface":"ワセリン","score":100.0}]}
         ]"#,
-    )));
+    ));
 
     for ch in "wase".chars() {
         engine.process_key(&press(ch));
@@ -88,9 +88,9 @@ fn pending_romaji_narrows_predictive_candidates() {
 #[test]
 fn dead_romaji_tail_suppresses_prediction() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[{"reading":"わせだ","candidates":[{"surface":"早稲田","score":1000.0}]}]"#,
-    )));
+    ));
 
     for ch in "waseyk".chars() {
         engine.process_key(&press(ch));
@@ -109,7 +109,7 @@ fn dead_romaji_tail_suppresses_prediction() {
 #[test]
 fn conversion_list_gets_all_predictive_candidates() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[
             {"reading":"わせだ","candidates":[{"surface":"早稲田","score":1000.0}]},
             {"reading":"わせだし","candidates":[{"surface":"早稲田市","score":2000.0}]},
@@ -117,7 +117,7 @@ fn conversion_list_gets_all_predictive_candidates() {
             {"reading":"わせだまえ","candidates":[{"surface":"早稲田前","score":4000.0}]},
             {"reading":"わせだえき","candidates":[{"surface":"早稲田駅","score":5000.0}]}
         ]"#,
-    )));
+    ));
 
     let conversion: Vec<String> = engine
         .build_conversion_candidates("わせ", "わせ", "", 1, LearningLookup::Use)
@@ -142,12 +142,12 @@ fn conversion_list_gets_all_predictive_candidates() {
 #[test]
 fn conversion_with_pending_keeps_narrowed_candidates() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[
             {"reading":"わせだ","candidates":[{"surface":"早稲田","score":1000.0}]},
             {"reading":"わせりん","candidates":[{"surface":"ワセリン","score":100.0}]}
         ]"#,
-    )));
+    ));
 
     for ch in "wased".chars() {
         engine.process_key(&press(ch));
@@ -193,9 +193,9 @@ fn conversion_texts(engine: &mut InputMethodEngine, romaji: &str) -> Vec<String>
 #[test]
 fn conversion_ranks_user_predictive_after_model() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"けいざいいみん","candidates":[{"surface":"経済移民","score":1000.0}]}]"#,
-    )));
+    ));
     seed_model_cache(&mut engine, "ケイザイ", "", &["経済"]);
 
     let texts = conversion_texts(&mut engine, "keizai");
@@ -207,12 +207,12 @@ fn conversion_ranks_user_predictive_after_model() {
 #[test]
 fn conversion_keeps_user_exact_match_ahead_of_model() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
             {"reading":"けいざい","candidates":[{"surface":"経財","score":1000.0}]},
             {"reading":"けいざいいみん","candidates":[{"surface":"経済移民","score":1000.0}]}
         ]"#,
-    )));
+    ));
     seed_model_cache(&mut engine, "ケイザイ", "", &["経済"]);
 
     let texts = conversion_texts(&mut engine, "keizai");
@@ -225,18 +225,18 @@ fn conversion_keeps_user_exact_match_ahead_of_model() {
 #[test]
 fn conversion_ranks_exact_matches_ahead_of_predictive_across_dictionaries() {
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
             {"reading":"けいざい","candidates":[{"surface":"経財","score":1000.0}]},
             {"reading":"けいざいいみん","candidates":[{"surface":"経済移民","score":1000.0}]}
         ]"#,
-    )));
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    ));
+    engine.dicts.system = Some(dict_from_json(
         r#"[
             {"reading":"けいざい","candidates":[{"surface":"軽罪","score":1000.0}]},
             {"reading":"けいざいがく","candidates":[{"surface":"経済学","score":1000.0}]}
         ]"#,
-    )));
+    ));
     seed_model_cache(&mut engine, "ケイザイ", "", &["経済"]);
 
     let texts = conversion_texts(&mut engine, "keizai");
diff --git a/karukan-im/core/src/core/engine/tests/prefer.rs b/karukan-im/core/src/core/engine/tests/prefer.rs
new file mode 100644
index 0000000..61c1c86
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/prefer.rs
@@ -0,0 +1,1391 @@
+//! Learning judged in context, counters after a number, and learned words
+//! inside a sentence (see `engine::prefer`). The model is stood in for by
+//! the two caches: its conversions and its log-probabilities.
+
+use super::*;
+
+const SYSTEM: &str = r#"[
+    {"reading":"さい","candidates":[{"surface":"最","score":0.0},{"surface":"再","score":1.0},{"surface":"才","score":2.0},{"surface":"歳","score":3.0},{"surface":"際","score":4.0}]},
+    {"reading":"みみ","candidates":[{"surface":"耳","score":0.0},{"surface":"mimi","score":1.0}]}
+]"#;
+const COUNTERS: &str = r#"[
+    {"reading":"〈数〉さい","candidates":[{"surface":"歳","score":0.0}]},
+    {"reading":"〈数〉かい","candidates":[{"surface":"回","score":0.0},{"surface":"階","score":1.0}]}
+]"#;
+
+fn engine(learned: &[(&str, &str)]) -> InputMethodEngine {
+    let mut engine = InputMethodEngine::new();
+    engine.config.prediction = false;
+    engine.config.alphabet_candidates = false;
+    engine.dicts.system = Some(dict_from_json(SYSTEM));
+    engine.dicts.user = Some(dict_from_json(COUNTERS));
+    let mut cache = karukan_engine::LearningCache::new(Default::default());
+    for (reading, surface) in learned {
+        cache.record(reading, surface);
+    }
+    engine.learning = Some(cache);
+    engine
+}
+
+fn score(engine: &mut InputMethodEngine, reading: &str, lctx: &str, scores: &[(&str, f32)]) {
+    for (surface, value) in scores {
+        engine.score_cache.insert(
+            crate::core::engine::cache::ModelRole::Main,
+            reading,
+            lctx,
+            surface,
+            *value,
+        );
+    }
+}
+
+/// The model as measured on jinen-v2-small: さい alone, and after 18.
+fn seed_sai(engine: &mut InputMethodEngine) {
+    seed_model_cache(engine, "サイ", "", &["最"]);
+    seed_model_cache(engine, "サイ", "18", &["才"]);
+    score(
+        engine,
+        "さい",
+        "",
+        &[("最", -1.32), ("再", -1.32), ("歳", -7.06), ("才", -5.30)],
+    );
+    score(
+        engine,
+        "さい",
+        "18",
+        &[("才", -0.40), ("歳", -2.15), ("再", -3.54)],
+    );
+}
+
+/// みみ alone, after 今日は, and inside two sentences.
+fn seed_mimi(engine: &mut InputMethodEngine) {
+    seed_model_cache(engine, "ミミ", "", &["耳"]);
+    seed_model_cache(engine, "ミミ", "今日は", &["耳"]);
+    seed_model_cache(engine, "ミミガスキ", "", &["耳が好き"]);
+    seed_model_cache(engine, "ミミヲスマス", "", &["耳を澄ます"]);
+    score(engine, "みみ", "", &[("耳", -0.61), ("ミミ", -2.66)]);
+    score(engine, "みみ", "今日は", &[("耳", -0.27), ("ミミ", -2.32)]);
+    score(
+        engine,
+        "みみがすき",
+        "",
+        &[("耳が好き", -0.04), ("ミミが好き", -4.36)],
+    );
+    score(
+        engine,
+        "みみをすます",
+        "",
+        &[("耳を澄ます", -0.29), ("ミミを澄ます", -7.27)],
+    );
+}
+
+fn type_keys(engine: &mut InputMethodEngine, romaji: &str) {
+    for ch in romaji.chars() {
+        engine.process_key(&press(ch));
+    }
+}
+
+fn space(engine: &mut InputMethodEngine, romaji: &str) -> Vec<String> {
+    type_keys(engine, romaji);
+    engine.process_key(&press_key(Keysym::SPACE));
+    engine
+        .candidates()
+        .unwrap()
+        .candidates()
+        .iter()
+        .map(|c| c.text.clone())
+        .collect()
+}
+
+fn live(engine: &mut InputMethodEngine, romaji: &str) -> String {
+    engine.live.enabled = true;
+    type_keys(engine, romaji);
+    engine.preedit().unwrap().text().to_string()
+}
+
+fn learned(engine: &InputMethodEngine, reading: &str) -> Vec<String> {
+    engine
+        .learning
+        .as_ref()
+        .unwrap()
+        .lookup(reading)
+        .into_iter()
+        .map(|(surface, _)| surface)
+        .collect()
+}
+
+#[test]
+fn learning_leads_when_nothing_is_on_the_left() {
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    assert_eq!(space(&mut e, "sai")[0], "再");
+}
+
+#[test]
+fn live_conversion_shows_what_was_learned() {
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    assert_eq!(live(&mut e, "sai"), "再");
+}
+
+#[test]
+fn a_number_on_the_left_overrules_learning() {
+    // 18|さい: the model's margin against 再 grows by 3.1 once 18 is there.
+    let mut e = engine(&[("さい", "再")]);
+    e.dicts.user = None;
+    seed_sai(&mut e);
+    e.set_surrounding_context("18", "");
+    let list = space(&mut e, "sai");
+    assert_eq!(&list[..2], ["才", "再"], "{list:?}");
+}
+
+#[test]
+fn a_counter_leads_after_a_number() {
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    e.set_surrounding_context("18", "");
+    let list = space(&mut e, "sai");
+    assert_eq!(list[0], "歳", "{list:?}");
+    assert!(list.contains(&"再".to_string()), "{list:?}");
+}
+
+#[test]
+fn a_counter_leads_in_live_conversion_and_inside_the_composition() {
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    assert_eq!(live(&mut e, "18sai"), "18歳");
+    engine_space_first(&mut e, "18歳");
+}
+
+fn engine_space_first(e: &mut InputMethodEngine, expected: &str) {
+    e.process_key(&press_key(Keysym::SPACE));
+    let first = e.candidates().unwrap().candidates()[0].text.clone();
+    assert_eq!(first, expected);
+}
+
+#[test]
+fn several_counters_are_left_to_the_model() {
+    let mut e = engine(&[]);
+    seed_model_cache(&mut e, "カイ", "3", &["会"]);
+    score(&mut e, "かい", "3", &[("回", -0.72), ("階", -0.71)]);
+    e.set_surrounding_context("3", "");
+    assert_eq!(space(&mut e, "kai")[0], "階");
+}
+
+#[test]
+fn context_that_does_not_object_keeps_learning() {
+    let mut e = engine(&[("みみ", "ミミ")]);
+    seed_mimi(&mut e);
+    e.set_surrounding_context("今日は", "");
+    assert_eq!(space(&mut e, "mimi")[0], "ミミ");
+}
+
+#[test]
+fn a_choice_after_a_number_is_kept_apart() {
+    let mut e = engine(&[("さい", "再")]);
+    e.dicts.user = None;
+    seed_sai(&mut e);
+    e.set_surrounding_context("18", "");
+    // 才, 再, then pick 歳 from the list and commit it.
+    let list = space(&mut e, "sai");
+    let at = list.iter().position(|t| t == "歳").unwrap();
+    for _ in 0..at {
+        e.process_key(&press_key(Keysym::SPACE));
+    }
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "〈数〉さい"), ["歳"]);
+    assert_eq!(learned(&e, "さい"), ["再"]);
+
+    // After another number it leads; alone, さい is still 再.
+    e.set_surrounding_context("20", "");
+    seed_model_cache(&mut e, "サイ", "20", &["才"]);
+    assert_eq!(space(&mut e, "sai")[0], "歳");
+    e.process_key(&press_key(Keysym::ESCAPE));
+    e.process_key(&press_key(Keysym::ESCAPE));
+    e.set_surrounding_context("", "");
+    assert_eq!(space(&mut e, "sai")[0], "再");
+}
+
+#[test]
+fn a_number_typed_with_its_counter_is_learned_without_the_number() {
+    let mut e = engine(&[]);
+    e.dicts.user = None;
+    seed_sai(&mut e);
+    let list = space(&mut e, "18sai");
+    let at = list
+        .iter()
+        .position(|t| t == "18歳")
+        .expect("18歳 in the list");
+    for _ in 0..at {
+        e.process_key(&press_key(Keysym::SPACE));
+    }
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "〈数〉さい"), ["歳"]);
+    assert!(learned(&e, "18さい").is_empty());
+    seed_model_cache(&mut e, "サイ", "20", &["才"]);
+    assert_eq!(space(&mut e, "20sai")[0], "20歳");
+}
+
+#[test]
+fn a_learned_word_is_used_inside_a_sentence() {
+    let mut e = engine(&[("みみ", "ミミ")]);
+    seed_mimi(&mut e);
+    assert_eq!(live(&mut e, "mimigasuki"), "ミミが好き");
+    e.process_key(&press_key(Keysym::SPACE));
+    let list: Vec<String> = e
+        .candidates()
+        .unwrap()
+        .candidates()
+        .iter()
+        .map(|c| c.text.clone())
+        .collect();
+    assert_eq!(&list[..2], ["ミミが好き", "耳が好き"], "{list:?}");
+}
+
+#[test]
+fn a_sentence_that_objects_keeps_the_models_word() {
+    let mut e = engine(&[("みみ", "ミミ")]);
+    seed_mimi(&mut e);
+    assert_eq!(live(&mut e, "mimiwosumasu"), "耳を澄ます");
+    e.process_key(&press_key(Keysym::SPACE));
+    let list: Vec<String> = e
+        .candidates()
+        .unwrap()
+        .candidates()
+        .iter()
+        .map(|c| c.text.clone())
+        .collect();
+    assert_eq!(&list[..2], ["耳を澄ます", "ミミを澄ます"], "{list:?}");
+}
+
+#[test]
+fn a_word_inside_a_compound_is_left_alone() {
+    // 最 in 最高 is not the さい that was learned as 再.
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    seed_model_cache(&mut e, "サイコウ", "", &["最高"]);
+    let list = space(&mut e, "saikou");
+    assert_eq!(list[0], "最高");
+    assert!(!list.iter().any(|t| t == "再高"), "{list:?}");
+}
+
+#[test]
+fn kana_inside_kana_is_left_alone() {
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    seed_model_cache(&mut e, "クダサイネ", "", &["くださいね"]);
+    assert_eq!(live(&mut e, "kudasaine"), "くださいね");
+}
+
+#[test]
+fn a_counter_opens_a_longer_reading() {
+    let mut e = engine(&[]);
+    seed_model_cache(&mut e, "サイノトキ", "18", &["才のとき"]);
+    e.set_surrounding_context("18", "");
+    assert_eq!(live(&mut e, "sainotoki"), "歳のとき");
+}
+
+#[test]
+fn live_text_committed_unchosen_is_not_learned() {
+    let mut e = engine(&[]);
+    seed_sai(&mut e);
+    assert_eq!(live(&mut e, "sai"), "最");
+    e.process_key(&press_key(Keysym::RETURN));
+    assert!(learned(&e, "さい").is_empty());
+}
+
+#[test]
+fn an_unchosen_commit_refreshes_what_is_already_learned() {
+    let mut e = engine(&[("さい", "再")]);
+    seed_sai(&mut e);
+    assert_eq!(live(&mut e, "sai"), "再");
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "さい"), ["再"]);
+    let count = e.learning.as_ref().unwrap().entry_count();
+    assert_eq!(count, 1);
+}
+
+#[test]
+fn a_learned_counter_can_be_deleted() {
+    let mut e = engine(&[("〈数〉さい", "才")]);
+    seed_sai(&mut e);
+    e.set_surrounding_context("18", "");
+    assert_eq!(space(&mut e, "sai")[0], "才");
+    e.process_key(&press_ctrl(Keysym::BACKSPACE));
+    assert!(learned(&e, "〈数〉さい").is_empty());
+}
+
+#[test]
+fn no_english_spelling_of_one_word() {
+    let mut e = engine(&[]);
+    seed_mimi(&mut e);
+    let list = space(&mut e, "mimigasuki");
+    assert!(!list.iter().any(|t| t.contains("mimi")), "{list:?}");
+}
+
+#[test]
+fn respellings_are_ranked_by_the_model() {
+    let json = r#"[{"reading":"たび","candidates":[{"surface":"旅","score":0.0},{"surface":"足袋","score":1.0},{"surface":"度","score":2.0}]}]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "ソノタビニ", "", &["その旅に"]);
+    score(
+        &mut e,
+        "そのたびに",
+        "",
+        &[("その旅に", -0.6), ("その足袋に", -5.0), ("その度に", -0.5)],
+    );
+    let list = space(&mut e, "sonotabini");
+    assert_eq!(
+        &list[..3],
+        ["その旅に", "その度に", "その足袋に"],
+        "{list:?}"
+    );
+}
+
+#[test]
+fn a_wide_margin_in_context_is_not_excused_by_a_wide_margin_without() {
+    // A kanji-leaning persona: ミミ trails 耳 by 4.9 even alone, so the
+    // growth to 6.9 inside the sentence looks small. It is still too far.
+    let mut e = engine(&[("みみ", "ミミ")]);
+    seed_model_cache(&mut e, "ミミ", "", &["耳"]);
+    seed_model_cache(&mut e, "ミミヲスマス", "", &["耳をすます"]);
+    score(&mut e, "みみ", "", &[("耳", -0.02), ("ミミ", -4.90)]);
+    score(
+        &mut e,
+        "みみをすます",
+        "",
+        &[("耳をすます", -0.44), ("ミミをすます", -7.29)],
+    );
+    assert_eq!(live(&mut e, "mimiwosumasu"), "耳をすます");
+}
+
+#[test]
+fn space_starts_from_the_text_on_screen() {
+    // Live conversion showed one model answer, the list leads with another.
+    let mut e = engine(&[]);
+    seed_model_cache(&mut e, "ミミヲスマス", "", &["耳をすます", "耳を澄ます"]);
+    e.live.enabled = true;
+    type_keys(&mut e, "mimiwosumasu");
+    set_live_text(&mut e, "耳を澄ます");
+    engine_space_first(&mut e, "耳を澄ます");
+}
+
+#[test]
+fn a_far_fetched_respelling_is_not_offered() {
+    let json = r#"[{"reading":"たび","candidates":[{"surface":"旅","score":0.0},{"surface":"足袋","score":1.0},{"surface":"度","score":2.0}]}]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "ソノタビニ", "", &["その旅に"]);
+    score(
+        &mut e,
+        "そのたびに",
+        "",
+        &[
+            ("その旅に", -0.6),
+            ("その足袋に", -20.0),
+            ("その度に", -0.5),
+        ],
+    );
+    let list = space(&mut e, "sonotabini");
+    assert!(list.contains(&"その度に".to_string()), "{list:?}");
+    assert!(!list.contains(&"その足袋に".to_string()), "{list:?}");
+}
+
+#[test]
+fn part_of_a_compound_is_not_respelled() {
+    // 輩 reads はい, but 後輩 is one word: no 後ハイ, 後杯.
+    let json = r#"[
+        {"reading":"はい","candidates":[{"surface":"ハイ","score":0.0},{"surface":"杯","score":1.0},{"surface":"輩","score":2.0}]},
+        {"reading":"こうはい","candidates":[{"surface":"後輩","score":0.0},{"surface":"交配","score":1.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "コウハイ", "", &["後輩"]);
+    let list = space(&mut e, "kouhai");
+    assert_eq!(&list[..2], ["後輩", "交配"], "{list:?}");
+    assert!(
+        !list.iter().any(|t| t == "後ハイ" || t == "後杯"),
+        "{list:?}"
+    );
+}
+
+#[test]
+fn a_word_left_in_hiragana_is_written_as_learned() {
+    let mut e = engine(&[("わたし", "私")]);
+    seed_model_cache(&mut e, "ワタシ", "", &["私"]);
+    seed_model_cache(&mut e, "ワタシハ", "", &["わたしは"]);
+    seed_model_cache(&mut e, "ソレデワタシハ", "", &["それでわたしは"]);
+    score(
+        &mut e,
+        "わたしは",
+        "",
+        &[("わたしは", -0.4), ("私は", -1.6)],
+    );
+    score(
+        &mut e,
+        "それでわたしは",
+        "",
+        &[("それでわたしは", -0.3), ("それで私は", -2.0)],
+    );
+    assert_eq!(live(&mut e, "watasiha"), "私は");
+    engine_space_first(&mut e, "私は");
+    for _ in 0..3 {
+        e.process_key(&press_key(Keysym::ESCAPE));
+    }
+    assert_eq!(live(&mut e, "soredewatasiha"), "それで私は");
+}
+
+#[test]
+fn hiragana_that_is_not_that_word_stays() {
+    // さい inside ください: not after a particle. にち inside こんにちは:
+    // far behind the model's own sentence.
+    let mut e = engine(&[("さい", "再"), ("にち", "日")]);
+    seed_model_cache(&mut e, "クダサイネ", "", &["くださいね"]);
+    seed_model_cache(&mut e, "コンニチハ", "", &["こんにちは"]);
+    score(
+        &mut e,
+        "こんにちは",
+        "",
+        &[("こんにちは", -0.1), ("こん日は", -9.0)],
+    );
+    assert_eq!(live(&mut e, "kudasaine"), "くださいね");
+    for _ in 0..3 {
+        e.process_key(&press_key(Keysym::ESCAPE));
+    }
+    assert_eq!(live(&mut e, "konnnitiha"), "こんにちは");
+}
+
+#[test]
+fn bare_kana_of_unknown_origin_does_not_outrank_a_real_spelling() {
+    // An older history: わたし → わたし written twenty times by commits
+    // nobody chose, わたし → 私 once.
+    let mut e = engine(&[("わたし", "私")]);
+    for _ in 0..20 {
+        e.learning.as_mut().unwrap().record("わたし", "わたし");
+    }
+    seed_model_cache(&mut e, "ワタシ", "", &["わたし"]);
+    assert_eq!(live(&mut e, "watasi"), "私");
+    engine_space_first(&mut e, "私");
+}
+
+#[test]
+fn the_last_pick_leads_whatever_was_used_more() {
+    let mut e = engine(&[]);
+    for _ in 0..5 {
+        e.learning.as_mut().unwrap().record("さい", "再");
+    }
+    seed_sai(&mut e);
+    let list = space(&mut e, "sai");
+    assert_eq!(list[0], "再");
+    let at = list.iter().position(|t| t == "際").unwrap();
+    for _ in 0..at {
+        e.process_key(&press_key(Keysym::SPACE));
+    }
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(space(&mut e, "sai")[0], "際");
+}
+
+const HASHI: &str = r#"[
+    {"reading":"はし","candidates":[{"surface":"橋","score":0.0},{"surface":"箸","score":1.0},{"surface":"端","score":2.0}]},
+    {"reading":"かわ","candidates":[{"surface":"川","score":0.0},{"surface":"皮","score":1.0}]}
+]"#;
+
+#[test]
+fn every_word_gets_its_dictionary_spellings_and_the_most_natural_leads() {
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(HASHI));
+    seed_model_cache(&mut e, "カワノハシヲワタル", "", &["皮の箸を渡る"]);
+    score(
+        &mut e,
+        "かわのはしをわたる",
+        "",
+        &[
+            ("皮の箸を渡る", -6.0),
+            ("川の箸を渡る", -4.0),
+            ("皮の橋を渡る", -3.0),
+            ("皮の端を渡る", -9.0),
+        ],
+    );
+    let list = space(&mut e, "kawanohasiwowataru");
+    // Both respellings beat the model's own sentence by more than the
+    // margin and go ahead of it, the likelier first.
+    assert_eq!(
+        &list[..4],
+        [
+            "皮の橋を渡る",
+            "川の箸を渡る",
+            "皮の箸を渡る",
+            "皮の端を渡る"
+        ],
+        "{list:?}"
+    );
+}
+
+#[test]
+fn word_alternatives_follow_the_models_sentence_without_scores() {
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(HASHI));
+    seed_model_cache(&mut e, "カワノハシヲワタル", "", &["川の橋を渡る"]);
+    let list = space(&mut e, "kawanohasiwowataru");
+    assert_eq!(list[0], "川の橋を渡る");
+    for text in ["皮の橋を渡る", "川の箸を渡る", "川の端を渡る"] {
+        assert!(list.contains(&text.to_string()), "{text} in {list:?}");
+    }
+}
+
+#[test]
+fn respelling_goes_on_from_the_improved_sentence() {
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(HASHI));
+    seed_model_cache(&mut e, "カワノハシヲワタル", "", &["皮の箸を渡る"]);
+    score(
+        &mut e,
+        "かわのはしをわたる",
+        "",
+        &[
+            ("皮の箸を渡る", -8.0),
+            ("川の箸を渡る", -6.5),
+            ("皮の橋を渡る", -5.0),
+            ("皮の端を渡る", -9.0),
+            ("川の橋を渡る", -0.5),
+            ("川の端を渡る", -7.0),
+        ],
+    );
+    let list = space(&mut e, "kawanohasiwowataru");
+    assert_eq!(
+        &list[..3],
+        ["川の橋を渡る", "皮の橋を渡る", "川の箸を渡る"],
+        "{list:?}"
+    );
+}
+
+#[test]
+fn what_was_just_committed_is_the_context_when_the_editor_reports_none() {
+    let mut e = engine(&[]);
+    e.learning = None;
+    seed_model_cache(&mut e, "カゼデ", "", &["風邪で"]);
+    seed_model_cache(&mut e, "ハナ", "風邪で", &["鼻"]);
+    seed_model_cache(&mut e, "ハナ", "", &["花"]);
+    type_keys(&mut e, "kazede");
+    e.process_key(&press_key(Keysym::SPACE));
+    e.process_key(&press_key(Keysym::RETURN));
+    // No surrounding text from the editor, as in a terminal.
+    e.set_surrounding_context("", "");
+    assert_eq!(space(&mut e, "hana")[0], "鼻");
+    e.process_key(&press_key(Keysym::RETURN));
+    // Enter reaches the editor: a new line, the context is gone.
+    e.process_key(&press_key(Keysym::RETURN));
+    e.set_surrounding_context("", "");
+    assert_eq!(space(&mut e, "hana")[0], "花");
+}
+
+#[test]
+fn the_editors_own_report_wins_over_the_engines_record() {
+    let mut e = engine(&[]);
+    seed_model_cache(&mut e, "カゼデ", "", &["風邪で"]);
+    seed_model_cache(&mut e, "ハナ", "庭に", &["花"]);
+    type_keys(&mut e, "kazede");
+    e.process_key(&press_key(Keysym::SPACE));
+    e.process_key(&press_key(Keysym::RETURN));
+    e.set_surrounding_context("庭に", "");
+    assert_eq!(space(&mut e, "hana")[0], "花");
+}
+
+#[test]
+fn a_word_gets_every_dictionary_spelling() {
+    // はなに: 鼻 is the dictionary's ninth spelling of はな.
+    let json = r#"[{"reading":"はな","candidates":[{"surface":"華","score":0.0},{"surface":"来栖華","score":1.0},{"surface":"ハナ","score":2.0},{"surface":"花","score":3.0},{"surface":"洟","score":4.0},{"surface":"端","score":5.0},{"surface":"葉名","score":6.0},{"surface":"波奈","score":7.0},{"surface":"鼻","score":8.0}]}]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "ハナニ", "", &["花に"]);
+    score(
+        &mut e,
+        "はなに",
+        "",
+        &[
+            ("花に", -0.4),
+            ("華に", -3.0),
+            ("来栖華に", -20.0),
+            ("ハナに", -4.0),
+            ("洟に", -9.0),
+            ("端に", -5.0),
+            ("葉名に", -12.0),
+            ("波奈に", -13.0),
+            ("鼻に", -1.5),
+        ],
+    );
+    let list = space(&mut e, "hanani");
+    assert_eq!(&list[..3], ["花に", "鼻に", "華に"], "{list:?}");
+    assert!(!list.contains(&"来栖華に".to_string()), "{list:?}");
+}
+
+#[test]
+fn kanji_preference_lets_a_close_kanji_spelling_lead() {
+    let json = r#"[{"reading":"いろんな","candidates":[{"surface":"色んな","score":0.0}]},{"reading":"たんご","candidates":[{"surface":"単語","score":0.0},{"surface":"丹後","score":1.0}]}]"#;
+    let seed = |e: &mut InputMethodEngine| {
+        e.dicts.system = Some(dict_from_json(json));
+        seed_model_cache(e, "イロンナタンゴ", "", &["いろんな単語"]);
+        score(
+            e,
+            "いろんなたんご",
+            "",
+            &[
+                ("いろんな単語", -0.3),
+                ("色んな単語", -1.4),
+                ("いろんな丹後", -6.0),
+                ("色んな丹後", -7.5),
+            ],
+        );
+    };
+    let mut e = engine(&[]);
+    seed(&mut e);
+    assert_eq!(space(&mut e, "ironnnatango")[0], "いろんな単語");
+    let mut e = engine(&[]);
+    e.config.kanji_preference = 2.0;
+    seed(&mut e);
+    let list = space(&mut e, "ironnnatango");
+    assert_eq!(&list[..2], ["色んな単語", "いろんな単語"], "{list:?}");
+}
+
+#[test]
+fn a_choice_teaches_the_word_for_other_sentences() {
+    let json = r#"[{"reading":"いろんな","candidates":[{"surface":"色んな","score":0.0}]},{"reading":"たんご","candidates":[{"surface":"単語","score":0.0}]}]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "イロンナタンゴ", "", &["いろんな単語"]);
+    seed_model_cache(&mut e, "イロンナヒト", "", &["いろんな人"]);
+    score(
+        &mut e,
+        "いろんなひと",
+        "",
+        &[("いろんな人", -0.3), ("色んな人", -1.9)],
+    );
+    let list = space(&mut e, "ironnnatango");
+    let at = list.iter().position(|t| t == "色んな単語").unwrap();
+    for _ in 0..at {
+        e.process_key(&press_key(Keysym::SPACE));
+    }
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "いろんな"), ["色んな"]);
+    // Enter reached the editor's line; start afresh.
+    e.set_surrounding_context("", "");
+    e.reset();
+    assert_eq!(space(&mut e, "ironnnahito")[0], "色んな人");
+}
+
+#[test]
+fn a_commoner_kanji_word_leads_over_the_bare_kana() {
+    // Costs as in Mozc: 明日 3087 < あした 4339; ありがとう 646 < 有難う 2392.
+    let json = r#"[
+        {"reading":"あした","candidates":[{"surface":"明日","score":3087.0},{"surface":"あした","score":4339.0}]},
+        {"reading":"ありがとう","candidates":[{"surface":"ありがとう","score":646.0},{"surface":"有難う","score":2392.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "アシタ", "", &["あした"]);
+    seed_model_cache(&mut e, "アリガトウ", "", &["ありがとう"]);
+    score(&mut e, "あした", "", &[("あした", -0.4), ("明日", -2.6)]);
+    score(
+        &mut e,
+        "ありがとう",
+        "",
+        &[("ありがとう", -0.1), ("有難う", -2.6)],
+    );
+    assert_eq!(space(&mut e, "asita")[0], "明日");
+    for _ in 0..3 {
+        e.process_key(&press_key(Keysym::ESCAPE));
+    }
+    assert_eq!(space(&mut e, "arigatou")[0], "ありがとう");
+}
+
+#[test]
+fn live_conversion_shows_the_commoner_word_for_a_bare_reading() {
+    let json = r#"[{"reading":"ぼく","candidates":[{"surface":"僕","score":1354.0},{"surface":"朴","score":4566.0}]}]"#;
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "ボク", "", &["朴"]);
+    score(&mut e, "ぼく", "", &[("朴", -1.5), ("僕", -1.6)]);
+    assert_eq!(live(&mut e, "boku"), "僕");
+    engine_space_first(&mut e, "僕");
+}
+
+/// Costs as in Mozc, scores as measured on jinen-v2-small.
+const NOTATION: &str = r#"[
+    {"reading":"いろんな","candidates":[{"surface":"いろんな","score":1603.0},{"surface":"色んな","score":1817.0}]},
+    {"reading":"いずれ","candidates":[{"surface":"何れ","score":931.0},{"surface":"いずれ","score":1853.0}]},
+    {"reading":"よろしく","candidates":[{"surface":"よろしく","score":2097.0},{"surface":"宜しく","score":2872.0}]},
+    {"reading":"たんご","candidates":[{"surface":"単語","score":2000.0}]},
+    {"reading":"ひと","candidates":[{"surface":"人","score":100.0}]}
+]"#;
+
+fn notation_engine() -> InputMethodEngine {
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(NOTATION));
+    seed_model_cache(&mut e, "イロンナタンゴ", "", &["いろんな単語"]);
+    seed_model_cache(&mut e, "イロンナヒト", "", &["いろんな人"]);
+    seed_model_cache(&mut e, "イズレニセヨ", "", &["いずれにせよ"]);
+    seed_model_cache(&mut e, "ヨロシクネ", "", &["よろしくね"]);
+    score(
+        &mut e,
+        "いろんな",
+        "",
+        &[("いろんな", -0.49), ("色んな", -0.96)],
+    );
+    score(&mut e, "いずれ", "", &[("いずれ", -0.14), ("何れ", -2.16)]);
+    score(
+        &mut e,
+        "いろんなたんご",
+        "",
+        &[("いろんな単語", -0.16), ("色んな単語", -2.05)],
+    );
+    score(
+        &mut e,
+        "いろんなひと",
+        "",
+        &[("いろんな人", -0.21), ("色んな人", -2.06)],
+    );
+    score(
+        &mut e,
+        "いずれにせよ",
+        "",
+        &[("いずれにせよ", -0.16), ("何れにせよ", -1.92)],
+    );
+    score(
+        &mut e,
+        "よろしくね",
+        "",
+        &[("よろしくね", -0.3), ("宜しくね", -1.4)],
+    );
+    e
+}
+
+#[test]
+fn a_common_kanji_spelling_leads_over_the_kana_the_model_left() {
+    let mut e = notation_engine();
+    let list = space(&mut e, "ironnnatango");
+    assert_eq!(&list[..2], ["色んな単語", "いろんな単語"], "{list:?}");
+    // Live conversion shows the same.
+    let mut e = notation_engine();
+    assert_eq!(live(&mut e, "ironnnatango"), "色んな単語");
+    engine_space_first(&mut e, "色んな単語");
+}
+
+#[test]
+fn kanji_the_model_minds_or_the_data_calls_rarer_does_not_lead() {
+    // 何れ: cheap in the data, but the model minds it for the bare word.
+    let mut e = notation_engine();
+    let list = space(&mut e, "izureniseyo");
+    assert_eq!(&list[..2], ["いずれにせよ", "何れにせよ"], "{list:?}");
+    // 宜しく: the kana is far commoner.
+    let mut e = notation_engine();
+    let list = space(&mut e, "yorosikune");
+    assert_eq!(&list[..2], ["よろしくね", "宜しくね"], "{list:?}");
+    // A sentence that falls too far behind keeps the kana.
+    let mut e = notation_engine();
+    score(&mut e, "いろんなたんご", "", &[("色んな単語", -3.2)]);
+    assert_eq!(space(&mut e, "ironnnatango")[0], "いろんな単語");
+    // Without frequency data in use there is nothing to go by.
+    let mut e = notation_engine();
+    e.config.word_prior = 0.0;
+    assert_eq!(space(&mut e, "ironnnatango")[0], "いろんな単語");
+}
+
+#[test]
+fn keeping_the_kana_is_a_choice_too() {
+    let mut e = notation_engine();
+    let list = space(&mut e, "ironnnatango");
+    assert_eq!(list[1], "いろんな単語", "{list:?}");
+    e.process_key(&press_key(Keysym::SPACE));
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "いろんな"), ["いろんな"]);
+    e.set_surrounding_context("", "");
+    e.reset();
+    assert_eq!(space(&mut e, "ironnnahito")[0], "いろんな人");
+}
+
+const COMPOUNDS: &str = r#"[
+    {"reading":"へんかん","candidates":[{"surface":"変換","score":0.0},{"surface":"返還","score":4725.0}]},
+    {"reading":"せいど","candidates":[{"surface":"制度","score":3456.0},{"surface":"精度","score":4122.0}]},
+    {"reading":"わるい","candidates":[{"surface":"悪い","score":1734.0}]}
+]"#;
+
+fn compound_engine(pair: f32) -> InputMethodEngine {
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(COMPOUNDS));
+    seed_model_cache(&mut e, "ヘンカンセイドガワルイ", "", &["返還制度が悪い"]);
+    score(
+        &mut e,
+        "へんかんせいどがわるい",
+        "",
+        &[
+            ("返還制度が悪い", -0.37),
+            ("変換精度が悪い", pair),
+            ("変換制度が悪い", -4.22),
+            ("返還精度が悪い", -5.88),
+        ],
+    );
+    e
+}
+
+#[test]
+fn a_compound_is_offered_as_every_pair_of_its_words() {
+    // The model is sure of its pair: the others are offered behind it.
+    let mut e = compound_engine(-2.9);
+    let list = space(&mut e, "hennkannseidogawarui");
+    assert_eq!(
+        &list[..4],
+        [
+            "返還制度が悪い",
+            "変換精度が悪い",
+            "変換制度が悪い",
+            "返還精度が悪い"
+        ],
+        "{list:?}"
+    );
+}
+
+#[test]
+fn a_far_commoner_homophone_leads_where_the_model_sees_no_difference() {
+    let mut e = compound_engine(-1.23);
+    let list = space(&mut e, "hennkannseidogawarui");
+    assert_eq!(&list[..2], ["変換精度が悪い", "返還制度が悪い"], "{list:?}");
+}
+
+#[test]
+fn a_chosen_compound_is_written_that_way_in_other_sentences() {
+    let mut e = compound_engine(-2.9);
+    seed_model_cache(&mut e, "ヘンカンセイドヲアゲル", "", &["返還制度を上げる"]);
+    seed_model_cache(&mut e, "ヘンカンセイド", "", &["返還制度"]);
+    score(
+        &mut e,
+        "へんかんせいど",
+        "",
+        &[("返還制度", -0.28), ("変換精度", -1.78)],
+    );
+    score(
+        &mut e,
+        "へんかんせいどをあげる",
+        "",
+        &[("返還制度を上げる", -0.3), ("変換精度を上げる", -1.9)],
+    );
+    let list = space(&mut e, "hennkannseidogawarui");
+    assert_eq!(list[1], "変換精度が悪い", "{list:?}");
+    e.process_key(&press_key(Keysym::SPACE));
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "へんかんせいど"), ["変換精度"]);
+    e.set_surrounding_context("", "");
+    e.reset();
+    assert_eq!(space(&mut e, "hennkannseidowoageru")[0], "変換精度を上げる");
+}
+
+/// Costs as in the system dictionary (20000 and up: no frequency known),
+/// scores as measured on jinen-v2-small.
+const FUNCTION_WORDS: &str = r#"[
+    {"reading":"まで","candidates":[{"surface":"迄","score":7615.0},{"surface":"まで","score":20000.0},{"surface":"マデ","score":20001.0}]},
+    {"reading":"から","candidates":[{"surface":"カラ","score":3228.0},{"surface":"殻","score":5260.0},{"surface":"から","score":6768.0}]},
+    {"reading":"どこ","candidates":[{"surface":"何処","score":216.0},{"surface":"どこ","score":729.0}]},
+    {"reading":"ない","candidates":[{"surface":"ない","score":0.0},{"surface":"無い","score":0.0}]},
+    {"reading":"なに","candidates":[{"surface":"何","score":100.0},{"surface":"なに","score":300.0}]},
+    {"reading":"〈仮名〉から","candidates":[{"surface":"から","score":0.0}]},
+    {"reading":"〈仮名〉まで","candidates":[{"surface":"まで","score":0.0}]},
+    {"reading":"〈仮名〉ない","candidates":[{"surface":"ない","score":0.0}]},
+    {"reading":"わたし","candidates":[{"surface":"わたし","score":0.0},{"surface":"私","score":263.0}]},
+    {"reading":"らせんがん","candidates":[{"surface":"螺旋丸","score":20000.0}]},
+    {"reading":"あっぷでーと","candidates":[{"surface":"アップデート","score":3844.0},{"surface":"upd8","score":20000.0}]}
+]"#;
+
+fn function_word_engine() -> InputMethodEngine {
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(FUNCTION_WORDS));
+    for (katakana, top) in [
+        ("マデ", "まで"),
+        ("カラ", "から"),
+        ("ドコ", "どこ"),
+        ("ナイ", "ない"),
+        ("ナニ", "なに"),
+        ("ワタシ", "わたし"),
+        ("ラセンガン", "螺旋岩"),
+        ("アップデート", "Update"),
+    ] {
+        seed_model_cache(&mut e, katakana, "", &[top]);
+    }
+    score(
+        &mut e,
+        "まで",
+        "",
+        &[("まで", -0.08), ("迄", -2.78), ("マデ", -4.54)],
+    );
+    score(
+        &mut e,
+        "から",
+        "",
+        &[("から", -0.37), ("カラ", -3.43), ("殻", -3.12)],
+    );
+    score(&mut e, "どこ", "", &[("どこ", -0.33), ("何処", -1.43)]);
+    score(&mut e, "ない", "", &[("ない", -0.58), ("無い", -1.40)]);
+    score(&mut e, "わたし", "", &[("わたし", -0.48), ("私", -2.89)]);
+    score(&mut e, "なに", "", &[("なに", -0.5), ("何", -1.2)]);
+    score(
+        &mut e,
+        "らせんがん",
+        "",
+        &[("螺旋岩", -0.86), ("螺旋丸", -3.98)],
+    );
+    score(
+        &mut e,
+        "あっぷでーと",
+        "",
+        &[
+            ("アップデート", -1.33),
+            ("あっぷでーと", -13.33),
+            ("Update", -0.5),
+        ],
+    );
+    e
+}
+
+#[test]
+fn words_written_in_kana_stay_in_kana() {
+    for (romaji, kana) in [
+        ("made", "まで"),
+        ("kara", "から"),
+        ("doko", "どこ"),
+        ("nai", "ない"),
+    ] {
+        let mut e = function_word_engine();
+        assert_eq!(space(&mut e, romaji)[0], kana, "{romaji}");
+        let mut e = function_word_engine();
+        assert_eq!(live(&mut e, romaji), kana, "{romaji} (live)");
+    }
+    // …while a word as usual in kanji as in kana is converted.
+    let mut e = function_word_engine();
+    assert_eq!(space(&mut e, "watasi")[0], "私");
+    let mut e = function_word_engine();
+    assert_eq!(space(&mut e, "nani")[0], "何");
+}
+
+#[test]
+fn a_dictionary_word_leads_over_a_compound_the_model_made_up() {
+    let mut e = function_word_engine();
+    let list = space(&mut e, "rasenngann");
+    assert_eq!(&list[..2], ["螺旋丸", "螺旋岩"], "{list:?}");
+    let mut e = function_word_engine();
+    assert_eq!(live(&mut e, "rasenngann"), "螺旋丸");
+    // Far-fetched in the model's eyes, the dictionary's word stays behind.
+    let mut e = function_word_engine();
+    score(&mut e, "らせんがん", "", &[("螺旋丸", -5.2)]);
+    assert_eq!(space(&mut e, "rasenngann")[0], "螺旋岩");
+}
+
+#[test]
+fn an_english_answer_gives_way_to_the_katakana() {
+    let mut e = function_word_engine();
+    let list = space(&mut e, "appude-to");
+    assert_eq!(list[0], "アップデート", "{list:?}");
+    assert!(!list.contains(&"Update".to_string()), "{list:?}");
+    let mut e = function_word_engine();
+    assert_eq!(live(&mut e, "appude-to"), "アップデート");
+}
+
+/// Costs as in the system dictionary, scores as measured on jinen-v2-small.
+const CUTS: &str = r#"[
+    {"reading":"くろ","candidates":[{"surface":"黒","score":2000.0}]},
+    {"reading":"くろき","candidates":[{"surface":"黒木","score":5000.0}]},
+    {"reading":"ちょう","candidates":[{"surface":"蝶","score":4500.0}]},
+    {"reading":"きちょう","candidates":[{"surface":"貴重","score":3000.0},{"surface":"きちょう","score":9000.0}]},
+    {"reading":"〈仮名〉き","candidates":[{"surface":"き","score":0.0}]}
+]"#;
+
+fn cut_engine() -> InputMethodEngine {
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(CUTS));
+    seed_model_cache(&mut e, "クロキチョウ", "", &["黒き蝶"]);
+    score(
+        &mut e,
+        "くろきちょう",
+        "",
+        &[("黒き蝶", -0.08), ("黒貴重", -6.51), ("黒木蝶", -12.53)],
+    );
+    e
+}
+
+#[test]
+fn the_reading_is_also_cut_into_words_at_other_places() {
+    let e = cut_engine();
+    // Cheapest cut first; the sentence itself is left out.
+    let texts = |e: &InputMethodEngine| -> Vec<String> {
+        e.lattice_alternatives("くろきちょう", "黒き蝶", true)
+            .into_iter()
+            .map(|recut| recut.text)
+            .collect()
+    };
+    assert_eq!(texts(&e), ["黒貴重", "黒木蝶"]);
+    // Without the frequency data there is no telling a likely cut.
+    let mut e = cut_engine();
+    e.config.word_prior = 0.0;
+    assert!(texts(&e).is_empty());
+}
+
+#[test]
+fn other_cuts_are_offered_where_the_model_does_not_find_them_far_fetched() {
+    let mut e = cut_engine();
+    let list = space(&mut e, "kurokityou");
+    assert_eq!(&list[..2], ["黒き蝶", "黒貴重"], "{list:?}");
+    assert!(!list.contains(&"黒木蝶".to_string()), "{list:?}");
+}
+
+#[test]
+fn a_long_sentence_is_recut_phrase_by_phrase() {
+    let json = r#"[
+        {"reading":"ここ","candidates":[{"surface":"ここ","score":0.0},{"surface":"此処","score":3000.0}]},
+        {"reading":"きもの","candidates":[{"surface":"着物","score":3000.0}]},
+        {"reading":"はきもの","candidates":[{"surface":"履物","score":4000.0}]},
+        {"reading":"ぬぐ","candidates":[{"surface":"脱ぐ","score":3000.0}]},
+        {"reading":"〈仮名〉で","candidates":[{"surface":"で","score":0.0}]},
+        {"reading":"〈仮名〉は","candidates":[{"surface":"は","score":0.0}]},
+        {"reading":"〈仮名〉を","candidates":[{"surface":"を","score":0.0}]},
+        {"reading":"〈仮名〉では","candidates":[{"surface":"では","score":0.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.dicts.system = Some(dict_from_json(json));
+    let reading = "ここではきものをぬぐすごくながいぶんしょうのさいご";
+    let sentence = "ここでは着物を脱ぐすごく長い文章の最後";
+    let found: Vec<String> = e
+        .lattice_alternatives(reading, sentence, true)
+        .into_iter()
+        .map(|recut| recut.text)
+        .collect();
+    assert!(
+        found.contains(&"ここで履物を脱ぐすごく長い文章の最後".to_string()),
+        "{found:?}"
+    );
+}
+
+/// What the user chose before speaks for a spelling of another word.
+fn persona_engine() -> InputMethodEngine {
+    let json = r#"[
+        {"reading":"たぶん","candidates":[{"surface":"たぶん","score":1500.0},{"surface":"多分","score":2696.0}]},
+        {"reading":"だいじょうぶ","candidates":[{"surface":"大丈夫","score":1000.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.config.auto_persona = true;
+    e.dicts.system = Some(dict_from_json(json));
+    let cache = e.learning.as_mut().unwrap();
+    cache.record_chosen("でき", "出来");
+    cache.record_chosen("いろんな", "色んな");
+    seed_model_cache(&mut e, "タブンダイジョウブ", "", &["たぶん大丈夫"]);
+    score(
+        &mut e,
+        "たぶんだいじょうぶ",
+        "",
+        &[("たぶん大丈夫", -0.11), ("多分大丈夫", -0.25)],
+    );
+    e
+}
+
+#[test]
+fn the_users_own_words_speak_for_a_spelling_of_another_word() {
+    let mut e = persona_engine();
+    score(
+        &mut e,
+        "たぶんだいじょうぶ",
+        "出来 色んな",
+        &[("たぶん大丈夫", -4.6), ("多分大丈夫", -0.2)],
+    );
+    let list = space(&mut e, "tabunndaijoubu");
+    assert_eq!(&list[..2], ["多分大丈夫", "たぶん大丈夫"], "{list:?}");
+    assert_eq!(e.learned_persona, "出来 色んな");
+    // Live conversion shows the same.
+    let mut e = persona_engine();
+    score(
+        &mut e,
+        "たぶんだいじょうぶ",
+        "出来 色んな",
+        &[("たぶん大丈夫", -4.6), ("多分大丈夫", -0.2)],
+    );
+    assert_eq!(live(&mut e, "tabunndaijoubu"), "多分大丈夫");
+}
+
+#[test]
+fn the_persona_only_counts_for_what_it_changes() {
+    // The persona leaves the two as they were: nothing for it to say.
+    let mut e = persona_engine();
+    score(
+        &mut e,
+        "たぶんだいじょうぶ",
+        "出来 色んな",
+        &[("たぶん大丈夫", -0.2), ("多分大丈夫", -0.3)],
+    );
+    assert_eq!(space(&mut e, "tabunndaijoubu")[0], "たぶん大丈夫");
+    // A small move is as often chance as meaning.
+    let mut e = persona_engine();
+    score(
+        &mut e,
+        "たぶんだいじょうぶ",
+        "出来 色んな",
+        &[("たぶん大丈夫", -1.7), ("多分大丈夫", -0.25)],
+    );
+    assert_eq!(space(&mut e, "tabunndaijoubu")[0], "たぶん大丈夫");
+    // It speaks for 多分, but without it the model finds that far-fetched.
+    let mut e = persona_engine();
+    score(&mut e, "たぶんだいじょうぶ", "", &[("多分大丈夫", -3.4)]);
+    score(
+        &mut e,
+        "たぶんだいじょうぶ",
+        "出来 色んな",
+        &[("たぶん大丈夫", -4.6), ("多分大丈夫", -0.2)],
+    );
+    assert_eq!(space(&mut e, "tabunndaijoubu")[0], "たぶん大丈夫");
+    // Switched off, the learning record is not consulted this way.
+    let mut e = persona_engine();
+    e.config.auto_persona = false;
+    assert_eq!(space(&mut e, "tabunndaijoubu")[0], "たぶん大丈夫");
+    assert_eq!(e.learned_persona, "");
+}
+
+#[test]
+fn kanji_preference_shows_in_live_conversion_too() {
+    let json = r#"[{"reading":"いろんな","candidates":[{"surface":"色んな","score":0.0}]},{"reading":"たんご","candidates":[{"surface":"単語","score":0.0}]}]"#;
+    let mut e = engine(&[]);
+    e.config.kanji_preference = 2.0;
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "イロンナタンゴ", "", &["いろんな単語"]);
+    score(
+        &mut e,
+        "いろんなたんご",
+        "",
+        &[("いろんな単語", -0.3), ("色んな単語", -1.4)],
+    );
+    assert_eq!(live(&mut e, "ironnnatango"), "色んな単語");
+    engine_space_first(&mut e, "色んな単語");
+}
+
+#[test]
+fn a_picked_cut_teaches_its_words() {
+    let mut e = cut_engine();
+    let list = space(&mut e, "kurokityou");
+    assert_eq!(list[1], "黒貴重", "{list:?}");
+    e.process_key(&press_key(Keysym::SPACE));
+    e.process_key(&press_key(Keysym::RETURN));
+    assert_eq!(learned(&e, "きちょう"), ["貴重"]);
+    // In another sentence the cut with that word leads, as long as the
+    // model does not find it far-fetched.
+    e.set_surrounding_context("", "");
+    e.reset();
+    let json = format!(
+        "{}{}",
+        &CUTS[..CUTS.len() - 1],
+        r#",{"reading":"しろ","candidates":[{"surface":"白","score":2000.0}]}]"#
+    );
+    e.dicts.system = Some(dict_from_json(&json));
+    seed_model_cache(&mut e, "シロキチョウ", "", &["白き蝶"]);
+    score(
+        &mut e,
+        "しろきちょう",
+        "",
+        &[("白き蝶", -0.3), ("白貴重", -3.9)],
+    );
+    seed_model_cache(&mut e, "キチョウ", "", &["貴重"]);
+    score(&mut e, "きちょう", "", &[("貴重", -0.2)]);
+    assert_eq!(space(&mut e, "sirokityou")[0], "白貴重");
+}
+
+const FORMS: &str = r#"[
+    {"reading":"はなす","candidates":[{"surface":"話す","score":100.0},{"surface":"離す","score":2000.0}]},
+    {"reading":"かいもの","candidates":[{"surface":"買い物","score":500.0}]},
+    {"reading":"かい","candidates":[{"surface":"会","score":500.0},{"surface":"貝","score":3000.0}]},
+    {"reading":"〈活〉はなせ","candidates":[{"surface":"話せ","score":100.0},{"surface":"離せ","score":2000.0},{"surface":"放せ","score":2500.0}]},
+    {"reading":"〈活〉かい","candidates":[{"surface":"買い","score":300.0},{"surface":"書い","score":400.0},{"surface":"飼い","score":3000.0}]}
+]"#;
+
+#[test]
+fn a_conjugated_word_gets_the_other_verbs_of_its_reading() {
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(FORMS));
+    seed_model_cache(&mut e, "ソノコトハハナセナイ", "", &["そのことは話せない"]);
+    let list = space(&mut e, "sonokotohahanasenai");
+    assert_eq!(list[0], "そのことは話せない");
+    for text in ["そのことは離せない", "そのことは放せない"] {
+        assert!(list.contains(&text.to_string()), "{text} in {list:?}");
+    }
+    // Left in kana by the model, the verb is offered in kanji.
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(FORMS));
+    seed_model_cache(&mut e, "ハナセナイ", "", &["はなせない"]);
+    let list = space(&mut e, "hanasenai");
+    assert!(list.contains(&"話せない".to_string()), "{list:?}");
+}
+
+#[test]
+fn a_conjugated_form_is_not_taken_for_a_word_or_part_of_one() {
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(FORMS));
+    // 買い in 買い物 is no conjugation going on: nothing follows in kana.
+    seed_model_cache(&mut e, "カイモノニイク", "", &["買い物に行く"]);
+    let list = space(&mut e, "kaimononiiku");
+    assert!(!list.iter().any(|t| t.contains("書い物")), "{list:?}");
+    // 会 is a word: no form stands in for it, and it for none.
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(FORMS));
+    seed_model_cache(&mut e, "カイニデル", "", &["会に出る"]);
+    let list = space(&mut e, "kainideru");
+    assert!(list.contains(&"貝に出る".to_string()), "{list:?}");
+    assert!(!list.iter().any(|t| t.contains("書い")), "{list:?}");
+    // Alone, the reading is not a form at all.
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(FORMS));
+    let list = space(&mut e, "kai");
+    assert!(!list.contains(&"書い".to_string()), "{list:?}");
+}
+
+#[test]
+fn kanji_preference_leaves_words_alone_that_are_as_good_as_always_kana() {
+    // Costs as in the system dictionary: ありがとう is far commoner than
+    // 有難う, ございます is a function word, すごい / 凄い are close.
+    let json = r#"[
+        {"reading":"ありがとう","candidates":[{"surface":"ありがとう","score":646.0},{"surface":"有難う","score":2392.0}]},
+        {"reading":"ございます","candidates":[{"surface":"御座います","score":3000.0}]},
+        {"reading":"〈仮名〉ございます","candidates":[{"surface":"ございます","score":0.0}]},
+        {"reading":"できる","candidates":[{"surface":"できる","score":0.0},{"surface":"出来る","score":804.0}]},
+        {"reading":"〈仮名〉できる","candidates":[{"surface":"できる","score":0.0}]},
+        {"reading":"すごい","candidates":[{"surface":"すごい","score":1867.0},{"surface":"凄い","score":2439.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.config.kanji_preference = 2.0;
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(
+        &mut e,
+        "アリガトウゴザイマス",
+        "",
+        &["ありがとうございます"],
+    );
+    score(
+        &mut e,
+        "ありがとうございます",
+        "",
+        &[
+            ("ありがとうございます", -0.1),
+            ("有難うございます", -1.2),
+            ("ありがとう御座います", -1.5),
+        ],
+    );
+    assert_eq!(live(&mut e, "arigatougozaimasu"), "ありがとうございます");
+    let list = space_again(&mut e);
+    assert_eq!(list[0], "ありがとうございます", "{list:?}");
+    assert!(list.contains(&"有難うございます".to_string()), "{list:?}");
+    // A word about as usual in kanji follows the preference.
+    let mut e = engine(&[]);
+    e.config.word_prior = 0.3;
+    e.config.kanji_preference = 2.0;
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "スゴイネ", "", &["すごいね"]);
+    score(
+        &mut e,
+        "すごいね",
+        "",
+        &[("すごいね", -0.2), ("凄いね", -1.3)],
+    );
+    assert_eq!(live(&mut e, "sugoine"), "凄いね");
+    // So does a function word whose kanji is not far behind: a matter of
+    // taste, and the preference is the user's taste.
+    seed_model_cache(&mut e, "デキルヨ", "", &["できるよ"]);
+    score(
+        &mut e,
+        "できるよ",
+        "",
+        &[("できるよ", -0.3), ("出来るよ", -1.4)],
+    );
+    e.reset();
+    assert_eq!(live(&mut e, "dekiruyo"), "出来るよ");
+}
+
+/// Space on what is already typed: the candidate texts.
+fn space_again(e: &mut InputMethodEngine) -> Vec<String> {
+    e.process_key(&press_key(Keysym::SPACE));
+    e.candidates()
+        .unwrap()
+        .candidates()
+        .iter()
+        .map(|c| c.text.clone())
+        .collect()
+}
+
+#[test]
+fn kana_that_only_reads_like_a_word_does_not_hide_the_word_behind_it() {
+    // は|で of それはできない reads like 派手; できない begins inside it.
+    let json = r#"[
+        {"reading":"はで","candidates":[{"surface":"派手","score":3000.0}]},
+        {"reading":"できない","candidates":[{"surface":"出来ない","score":3000.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "ソレハデキナイ", "", &["それはできない"]);
+    let list = space(&mut e, "sorehadekinai");
+    assert!(list.contains(&"それは出来ない".to_string()), "{list:?}");
+}
+
+#[test]
+fn kanji_preference_leaves_a_bare_word_alone_that_is_as_good_as_always_kana() {
+    let json = r#"[
+        {"reading":"そうする","candidates":[{"surface":"そうする","score":1893.0},{"surface":"奏する","score":4111.0}]},
+        {"reading":"たくさん","candidates":[{"surface":"たくさん","score":2148.0},{"surface":"沢山","score":3013.0}]}
+    ]"#;
+    let seed = |e: &mut InputMethodEngine| {
+        e.config.word_prior = 0.3;
+        e.config.kanji_preference = 2.0;
+        e.dicts.system = Some(dict_from_json(json));
+        seed_model_cache(e, "ソウスル", "", &["そうする"]);
+        seed_model_cache(e, "タクサン", "", &["たくさん"]);
+        score(e, "そうする", "", &[("そうする", -0.2), ("奏する", -1.0)]);
+        score(e, "たくさん", "", &[("たくさん", -0.2), ("沢山", -1.0)]);
+    };
+    let mut e = engine(&[]);
+    seed(&mut e);
+    assert_eq!(space(&mut e, "sousuru")[0], "そうする");
+    let mut e = engine(&[]);
+    seed(&mut e);
+    assert_eq!(space(&mut e, "takusann")[0], "沢山");
+}
+
+#[test]
+fn a_verb_is_found_inside_kana_that_also_reads_as_a_longer_word() {
+    // かいた is a place name too (頴田); the verb is 書い|た, 描い|た.
+    let json = r#"[
+        {"reading":"かいた","candidates":[{"surface":"頴田","score":8000.0}]},
+        {"reading":"〈活〉かい","candidates":[{"surface":"書い","score":400.0},{"surface":"描い","score":900.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "エヲカイタ", "", &["絵をかいた"]);
+    let list = space(&mut e, "ewokaita");
+    for text in ["絵を書いた", "絵を描いた", "絵を頴田"] {
+        assert!(list.contains(&text.to_string()), "{text} in {list:?}");
+    }
+}
+
+#[test]
+fn kana_that_begins_with_a_particle_does_not_hide_the_word_behind_it() {
+    // にの is a name too (ニノ); after 相談 it is に and the verb のっ|た.
+    let json = r#"[
+        {"reading":"そうだん","candidates":[{"surface":"相談","score":1500.0}]},
+        {"reading":"にの","candidates":[{"surface":"ニノ","score":4387.0}]},
+        {"reading":"〈活〉のっ","candidates":[{"surface":"乗っ","score":2196.0},{"surface":"載っ","score":2921.0}]}
+    ]"#;
+    let mut e = engine(&[]);
+    e.dicts.system = Some(dict_from_json(json));
+    seed_model_cache(&mut e, "ソウダンニノッタ", "", &["相談にのった"]);
+    let list = space(&mut e, "soudannninotta");
+    for text in ["相談に乗った", "相談に載った"] {
+        assert!(list.contains(&text.to_string()), "{text} in {list:?}");
+    }
+}
diff --git a/karukan-im/core/src/core/engine/tests/rewriter.rs b/karukan-im/core/src/core/engine/tests/rewriter.rs
index c63cd13..8ba85d0 100644
--- a/karukan-im/core/src/core/engine/tests/rewriter.rs
+++ b/karukan-im/core/src/core/engine/tests/rewriter.rs
@@ -33,7 +33,7 @@ fn conversion_texts(reading: &str) -> Vec<String> {
 }
 
 /// Build a one-entry user dictionary and load it.
-fn user_dict_with(reading: &str, surface: &str) -> Dictionary {
+fn user_dict_with(reading: &str, surface: &str) -> std::sync::Arc<Dictionary> {
     dict_from_json(&format!(
         r#"[{{"reading":"{reading}","candidates":[{{"surface":"{surface}","score":1.0}}]}}]"#
     ))
@@ -126,7 +126,7 @@ fn rewriter_does_not_expand_dictionary_candidates() {
     // (wrongly) fed dictionary candidates, those three variants would
     // appear even though the user typed only hiragana.
     let mut engine = composing_engine("てすと");
-    engine.dicts.user = Some(std::sync::Arc::new(user_dict_with("てすと", ",")));
+    engine.dicts.user = Some(user_dict_with("てすと", ","));
 
     let texts: Vec<String> = engine
         .build_conversion_candidates("てすと", "てすと", "", 9, LearningLookup::Use)
diff --git a/karukan-im/core/src/core/engine/tests/shared_dicts.rs b/karukan-im/core/src/core/engine/tests/shared_dicts.rs
new file mode 100644
index 0000000..bd64610
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/shared_dicts.rs
@@ -0,0 +1,75 @@
+//! Engines in one process share the loaded system dictionary.
+
+use std::sync::{Arc, Mutex, MutexGuard};
+
+use super::*;
+
+/// The dictionary cache is process-wide and these tests run in parallel:
+/// without this lock one test's load evicts the other's cached copy.
+static CACHE_TESTS: Mutex<()> = Mutex::new(());
+
+fn serial() -> MutexGuard<'static, ()> {
+    CACHE_TESTS
+        .lock()
+        .unwrap_or_else(|poisoned| poisoned.into_inner())
+}
+
+fn write_dict(dir: &std::path::Path, name: &str, json: &str) -> std::path::PathBuf {
+    let dict = dict_from_json(json);
+    let path = dir.join(name);
+    dict.save(&path).unwrap();
+    path
+}
+
+#[test]
+fn test_engines_share_one_system_dictionary() {
+    let _serial = serial();
+    let dir = tempfile::tempdir().unwrap();
+    let path = write_dict(
+        dir.path(),
+        "dict.bin",
+        r#"[{"reading":"あい","candidates":[{"surface":"愛","score":1.0}]}]"#,
+    );
+    let path = path.to_str().unwrap();
+
+    let mut first = InputMethodEngine::new();
+    first.init_system_dictionary(Some(path));
+    let mut second = InputMethodEngine::new();
+    second.init_system_dictionary(Some(path));
+
+    let a = first.dicts.system.as_ref().expect("loaded");
+    let b = second.dicts.system.as_ref().expect("loaded");
+    assert!(
+        Arc::ptr_eq(a, b),
+        "the second engine must reuse the first copy"
+    );
+}
+
+#[test]
+fn test_rebuilt_dictionary_is_reloaded() {
+    let _serial = serial();
+    let dir = tempfile::tempdir().unwrap();
+    let path = write_dict(
+        dir.path(),
+        "dict.bin",
+        r#"[{"reading":"あい","candidates":[{"surface":"愛","score":1.0}]}]"#,
+    );
+    let path_str = path.to_str().unwrap().to_string();
+
+    let mut first = InputMethodEngine::new();
+    first.init_system_dictionary(Some(&path_str));
+
+    // Rebuild the file with different content (and so a different size).
+    write_dict(
+        dir.path(),
+        "dict.bin",
+        r#"[{"reading":"あい","candidates":[{"surface":"愛","score":1.0},{"surface":"藍","score":2.0}]},
+            {"reading":"うえ","candidates":[{"surface":"上","score":1.0}]}]"#,
+    );
+    let mut second = InputMethodEngine::new();
+    second.init_system_dictionary(Some(&path_str));
+
+    let fresh = second.dicts.system.as_ref().expect("loaded");
+    assert!(!Arc::ptr_eq(first.dicts.system.as_ref().unwrap(), fresh));
+    assert!(fresh.exact_match_search("うえ").is_some());
+}
diff --git a/karukan-im/core/src/core/engine/tests/source_filter.rs b/karukan-im/core/src/core/engine/tests/source_filter.rs
index a9ba927..f50a914 100644
--- a/karukan-im/core/src/core/engine/tests/source_filter.rs
+++ b/karukan-im/core/src/core/engine/tests/source_filter.rs
@@ -279,12 +279,12 @@ fn test_dictionary_view_prefix_matches_from_one_char() {
     // The dictionary views are full browsers: predictive matches kick in
     // from the very first char, unlike the mixed list's 2-char guard.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
         {"reading":"あ","candidates":[{"surface":"亜","score":1.0}]},
         {"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}
     ]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press_key(Keysym::SPACE));
@@ -309,12 +309,12 @@ fn test_typing_narrows_within_the_filtered_view() {
     // fzf-style: typing while a source view is active keeps the view and
     // narrows it with the grown reading.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
         {"reading":"あ","candidates":[{"surface":"亜","score":1.0}]},
         {"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}
     ]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press_key(Keysym::SPACE));
@@ -341,12 +341,12 @@ fn test_backspace_widens_within_the_filtered_view() {
     // The mirror of typing-refine: Backspace shrinks the reading and the
     // view re-expands; emptying the buffer exits cleanly.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
         {"reading":"あ","candidates":[{"surface":"亜","score":1.0}]},
         {"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}
     ]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
@@ -371,12 +371,12 @@ fn test_ctrl_h_widens_within_the_filtered_view() {
     // Ctrl+H follows the same filtered-view branch as Backspace, not the
     // plain cancel: the view stays open and the reading shrinks.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
         {"reading":"あ","candidates":[{"surface":"亜","score":1.0}]},
         {"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}
     ]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
@@ -767,12 +767,12 @@ fn test_dictionary_view_merges_both_dictionaries_user_first() {
     let mut engine = InputMethodEngine::new();
     // Deterministic model result (a cache hit stands in for the model).
     seed_model_cache(&mut engine, "アイ", "", &["合い"]);
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"あい","candidates":[{"surface":"藍","score":1.0}]}]"#,
-    )));
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    ));
+    engine.dicts.system = Some(dict_from_json(
         r#"[{"reading":"あい","candidates":[{"surface":"藍","score":1.0},{"surface":"愛","score":2.0}]}]"#,
-    )));
+    ));
 
     engine.process_key(&press('a'));
     engine.process_key(&press('i'));
@@ -1187,12 +1187,12 @@ fn test_filtered_view_aux_shows_what_is_being_typed() {
     // selected candidate's own reading, which for a predictive entry runs
     // past what was typed and left no sign of the actual input.
     let mut engine = InputMethodEngine::new();
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.user = Some(dict_from_json(
         r#"[
         {"reading":"わせだ","candidates":[{"surface":"早稲田","score":1.0}]},
         {"reading":"わせだだいがく","candidates":[{"surface":"早稲田大学","score":1.0}]}
     ]"#,
-    )));
+    ));
     for c in ['w', 'a', 's', 'e', 'd', 'a'] {
         engine.process_key(&press(c));
     }
diff --git a/karukan-im/core/src/core/engine/tests/user_dict_order.rs b/karukan-im/core/src/core/engine/tests/user_dict_order.rs
new file mode 100644
index 0000000..4caff15
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/user_dict_order.rs
@@ -0,0 +1,78 @@
+//! Where user-dictionary candidates land in the Space conversion list:
+//! exact matches lead, predictive completions follow the model.
+
+use super::*;
+
+fn engine_with_user_dict(json: &str) -> InputMethodEngine {
+    let mut engine = InputMethodEngine::new();
+    engine.converters.kanji = None;
+    engine.dicts.user = Some(dict_from_json(json));
+    engine
+}
+
+fn type_and_convert(engine: &mut InputMethodEngine, romaji: &str) {
+    for ch in romaji.chars() {
+        engine.process_key(&press(ch));
+    }
+    engine.process_key(&press_key(Keysym::SPACE));
+    assert!(matches!(engine.state(), InputState::Conversion { .. }));
+}
+
+fn texts(engine: &InputMethodEngine) -> Vec<String> {
+    engine
+        .candidates()
+        .unwrap()
+        .candidates()
+        .iter()
+        .map(|c| c.text.clone())
+        .collect()
+}
+
+#[test]
+fn test_predictive_user_dict_follows_the_model() {
+    // さと + Space must not select the completion 悟 (さとる) over the
+    // model's answer for さと itself.
+    let mut engine = engine_with_user_dict(
+        r#"[{"reading":"さとる","candidates":[{"surface":"悟","score":0.0}]}]"#,
+    );
+    seed_model_cache(&mut engine, "サト", "", &["里"]);
+    type_and_convert(&mut engine, "sato");
+
+    assert_eq!(engine.candidates().unwrap().selected_text(), Some("里"));
+    let list = texts(&engine);
+    let model_at = list.iter().position(|t| t == "里").unwrap();
+    let predictive_at = list
+        .iter()
+        .position(|t| t == "悟")
+        .expect("the completion stays in the list");
+    assert!(model_at < predictive_at, "list: {list:?}");
+}
+
+#[test]
+fn test_exact_user_dict_match_still_leads() {
+    let mut engine = engine_with_user_dict(
+        r#"[{"reading":"さと","candidates":[{"surface":"郷","score":0.0}]}]"#,
+    );
+    seed_model_cache(&mut engine, "サト", "", &["里"]);
+    type_and_convert(&mut engine, "sato");
+
+    assert_eq!(engine.candidates().unwrap().selected_text(), Some("郷"));
+}
+
+#[test]
+fn test_exact_system_matches_precede_predictive_user_entries() {
+    // ほし + Space: the system dictionary's exact 星 must not be pushed down
+    // by user-dictionary completions such as ほしの → 星野.
+    let mut engine = engine_with_user_dict(
+        r#"[{"reading":"ほしの","candidates":[{"surface":"星野","score":0.0}]}]"#,
+    );
+    engine.dicts.system = Some(dict_from_json(
+        r#"[{"reading":"ほし","candidates":[{"surface":"星","score":1.0}]}]"#,
+    ));
+    type_and_convert(&mut engine, "hosi");
+
+    let list = texts(&engine);
+    let exact_at = list.iter().position(|t| t == "星").expect("exact match");
+    let predictive_at = list.iter().position(|t| t == "星野").expect("completion");
+    assert!(exact_at < predictive_at, "list: {list:?}");
+}
diff --git a/karukan-im/core/src/core/engine/tests/width.rs b/karukan-im/core/src/core/engine/tests/width.rs
index 55c3301..4e020ce 100644
--- a/karukan-im/core/src/core/engine/tests/width.rs
+++ b/karukan-im/core/src/core/engine/tests/width.rs
@@ -210,12 +210,12 @@ fn dictionary_surfaces_keep_the_width_they_were_written_at() {
         ..WidthRules::default()
     });
     engine.converters.kanji = None;
-    engine.dicts.system = Some(std::sync::Arc::new(dict_from_json(
+    engine.dicts.system = Some(dict_from_json(
         r#"[{"reading":"かぶ","candidates":[{"surface":"Yahoo!","score":1.0}]}]"#,
-    )));
-    engine.dicts.user = Some(std::sync::Arc::new(dict_from_json(
+    ));
+    engine.dicts.user = Some(dict_from_json(
         r#"[{"reading":"かぶ","candidates":[{"surface":"１２３号","score":1.0}]}]"#,
-    )));
+    ));
 
     type_keys(&mut engine, "kabu");
     let result = engine.process_key(&press_key(Keysym::SPACE));
diff --git a/karukan-im/core/src/core/engine/tests/word_swap.rs b/karukan-im/core/src/core/engine/tests/word_swap.rs
new file mode 100644
index 0000000..57e5588
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/word_swap.rs
@@ -0,0 +1,61 @@
+//! Word-swap candidates: one word of the model's sentence replaced by its
+//! other dictionary spellings.
+
+use super::super::swap::word_swaps;
+use super::*;
+
+fn dict() -> std::sync::Arc<Dictionary> {
+    dict_from_json(
+        r#"[
+            {"reading":"たび","candidates":[{"surface":"旅","score":1.0},{"surface":"度","score":2.0},{"surface":"足袋","score":3.0}]},
+            {"reading":"でき","candidates":[{"surface":"出来","score":1.0}]},
+            {"reading":"に","candidates":[{"surface":"二","score":1.0}]}
+        ]"#,
+    )
+}
+
+#[test]
+fn swaps_the_word_before_the_shared_kana_tail() {
+    let d = dict();
+    let out = word_swaps(&[&d], "なになにのたびに", "何々の旅に", false);
+    assert_eq!(
+        out[..2],
+        ["何々の度に".to_string(), "何々の足袋に".to_string()]
+    );
+}
+
+#[test]
+fn spells_a_kana_word_with_the_dictionary() {
+    let d = dict();
+    let out = word_swaps(&[&d], "できていない", "できていない", false);
+    assert_eq!(out.first().map(String::as_str), Some("出来ていない"));
+}
+
+#[test]
+fn leaves_one_char_readings_alone() {
+    let d = dict();
+    let out = word_swaps(&[&d], "なになにのたびに", "何々の旅に", false);
+    assert!(!out.iter().any(|c| c.contains('二')), "{out:?}");
+}
+
+#[test]
+fn nothing_when_the_sentence_does_not_spell_the_word() {
+    let d = dict();
+    assert!(word_swaps(&[&d], "たびに", "TABIに", false).is_empty());
+    assert!(word_swaps(&[], "たびに", "旅に", false).is_empty());
+}
+
+#[test]
+fn skips_glosses_and_repeated_names() {
+    let d = dict_from_json(
+        r#"[
+            {"reading":"しろこ","candidates":[{"surface":"シロコ","score":1.0},{"surface":"砂狼シロコ","score":2.0},{"surface":"白子","score":3.0}]},
+            {"reading":"えんたく","candidates":[{"surface":"円卓","score":1.0},{"surface":"円卓（円卓）","score":2.0},{"surface":"円タク","score":3.0}]}
+        ]"#,
+    );
+    let out = word_swaps(&[&d], "すなおおかみしろこ", "砂狼シロコ", false);
+    assert!(out.contains(&"砂狼白子".to_string()), "{out:?}");
+    assert!(!out.iter().any(|c| c.contains("砂狼砂狼")), "{out:?}");
+    let out = word_swaps(&[&d], "えんたく", "円卓", false);
+    assert_eq!(out, ["円タク".to_string()]);
+}
diff --git a/karukan-im/core/src/core/engine/types.rs b/karukan-im/core/src/core/engine/types.rs
index 69eef2a..c04babb 100644
--- a/karukan-im/core/src/core/engine/types.rs
+++ b/karukan-im/core/src/core/engine/types.rs
@@ -113,6 +113,22 @@ pub struct EngineConfig {
     pub verbose: bool,
     /// Whether live conversion is enabled at engine startup
     pub live_conversion: bool,
+    /// Whether a printable keystroke during an unfiltered conversion commits
+    /// the selection and starts the next composition (MS-IME / mozc style)
+    /// instead of refining the reading in place
+    pub commit_on_input: bool,
+    /// Offer candidates whose reading extends the typed one (predictive
+    /// dictionary/learning completions); `false` keeps exact readings only
+    pub prediction: bool,
+    /// Offer Latin-only dictionary surfaces for a reading typed in kana
+    pub alphabet_candidates: bool,
+    /// Margin (nats) within which a conversion with more kanji leads; 0 = off
+    pub kanji_preference: f32,
+    /// Weight of dictionary word frequency for a single-word reading; 0 = off
+    pub word_prior: f32,
+    /// Put the user's own chosen words (from the learning record) in
+    /// front of the left context, after `persona`.
+    pub auto_persona: bool,
     /// When the candidate window (aux line included) opens
     pub candidate_window: CandidateWindow,
     /// Which symbol the `,` `.` `/` `[` `]` keys type
@@ -152,6 +168,12 @@ impl EngineConfig {
             strategy: settings.conversion.strategy,
             verbose: settings.display.verbose,
             live_conversion: settings.conversion.live_conversion,
+            commit_on_input: settings.conversion.commit_on_input,
+            prediction: settings.conversion.prediction,
+            alphabet_candidates: settings.conversion.alphabet_candidates,
+            kanji_preference: settings.conversion.kanji_preference,
+            word_prior: settings.conversion.word_prior,
+            auto_persona: settings.conversion.auto_persona,
             candidate_window: settings.display.candidate_window,
             symbol: settings.symbol.style(),
             width: settings.width,
@@ -180,6 +202,16 @@ impl Default for EngineConfig {
             strategy: StrategyMode::default(),
             verbose: false,
             live_conversion: false,
+            // The engine default keeps the refine-in-place behaviour; the
+            // shipped config.toml default (default.toml) turns it on.
+            commit_on_input: false,
+            // Engine defaults keep upstream's behaviour; the shipped
+            // default.toml turns both off.
+            prediction: true,
+            alphabet_candidates: true,
+            kanji_preference: 0.0,
+            word_prior: 0.0,
+            auto_persona: false,
             candidate_window: CandidateWindow::default(),
             symbol: SymbolStyle::default(),
             width: WidthRules::default(),
@@ -318,10 +350,10 @@ impl LiveConversion {
     }
 }
 
-/// Dictionary store: system, user, and future cache dictionaries
+/// Dictionary store: system, user, and future cache dictionaries.
 ///
-/// `Arc` allows the (expensive-to-load) merged user dictionary to be shared
-/// across per-context engine instances via a process-global cache.
+/// Both are shared (`Arc`): fcitx5 runs one engine per input context, and
+/// `init.rs` hands every engine in the process the same loaded copy.
 #[derive(Default)]
 pub(in crate::core) struct Dictionaries {
     /// System dictionary for yada double-array trie lookup
diff --git a/karukan-im/core/src/core/keycode.rs b/karukan-im/core/src/core/keycode.rs
index c8e8c17..4da5cfb 100644
--- a/karukan-im/core/src/core/keycode.rs
+++ b/karukan-im/core/src/core/keycode.rs
@@ -45,6 +45,8 @@ impl Keysym {
     /// same value). Delivered by fcitx5 for the key right of Space on JIS
     /// keyboards.
     pub const HENKAN: Keysym = Keysym(0xff23);
+    /// 無変換 key (XK_Muhenkan), left of Space on JIS keyboards.
+    pub const MUHENKAN: Keysym = Keysym(0xff22);
 
     // Space
     pub const SPACE: Keysym = Keysym(0x0020);
-- 
2.43.0

PATCH_EOF
echo "$PATCH_SHA256  karukan-kz.patch" | sha256sum --check --quiet \
    || die "書き出したパッチが壊れています。スクリプトをもう一度ダウンロードしてください。"

cat > PKGBUILD <<'PKGBUILD_EOF'
# Local package built by karukan-kz-install.sh — not from the AUR.
# Upstream Karukan (togatoga/karukan) plus the karukan-kz patch:
#   - [conversion] commit_on_input: typing during a conversion commits it
#   - 無変換 switches the kana type (カタカナ → ﾊﾝｶｸ → ひらがな), like mozc / MS-IME
#   - exact dictionary matches rank before predictive completions, and
#     predictive user-dictionary entries no longer outrank the model
#   - every input context shares one loaded copy of the dictionaries
#   - larger dictionary load limits, for extended system dictionaries
#   - word swaps: dictionary spellings for one word inside the model's sentence
#   - learned completions of longer past readings rank after the model
#   - [conversion] prediction / alphabet_candidates: exact readings only, no
#     Latin-only candidates for kana (shipped default: both off)
#   - ＠ character lookups (＠こいし): the dictionary's list, no model output
#   - learning judged in context by the model's own log-probabilities, used in
#     live conversion and inside sentences; counters after a number (18さい → 18歳);
#     unchosen commits are no longer learned; word swaps ranked by the model
#   - beams and swaps the main model finds far-fetched are dropped, a word inside
#     a compound is never swapped (後輩 → 後ハイ), and a learned spelling replaces
#     a word the model left in hiragana (わたしは → 私は)
#   - learning keeps only what was picked from the candidates (marked in a fifth
#     column; the last pick leads); a kana-to-same-kana row of unknown origin no
#     longer outranks a real spelling, and unchosen commits are not recorded at all
#   - every word of the model's sentence gets its dictionary spellings, all are
#     scored by the model, and what it finds clearly more natural leads
#   - revision 8: word frequency (Mozc costs stored in the system dictionary)
#     steadies bare words (ぼく → 僕, わたし → 私) while function words and
#     こそあど words stay in kana; common kanji spellings and far commoner
#     homophones lead where the model allows (色んな単語, 変換精度が悪い); a kanji
#     compound is offered as every pair of its words; a dictionary word leads
#     over a compound the model made up (螺旋丸); an English answer gives way to
#     katakana (アップデート); a choice teaches the word, not only the phrase;
#     what was just committed is the left context when the editor reports none;
#     plain symbols come before pictographs (はーと → ♡ ♥ ❤); live conversion
#     follows the same rules; scoring runs on a unified KV cache
#   - revision 9: the reading is also cut into words at other places (a word
#     lattice over the dictionaries; くろきちょう: 黒き蝶 → 黒木町, 黒基調; a long
#     sentence phrase by phrase) and the model judges those cuts with the rest;
#     the user's own chosen words (the learning record) judge between the
#     model's first answers as a persona (auto_persona); kanji_preference and
#     the persona show in live conversion too; sentences being scored share
#     the tokens they begin with, and a long sentence gets fewer alternatives
#     ; conjugated forms (話せ, 書い) are looked up under a mark so that a
#     conjugated verb gets the other verbs of its reading (離せない, 描いた)
# Based on the AUR karukan-git PKGBUILD by koh11235813.
pkgname=karukan-kz-git
pkgver=0
pkgrel=1
pkgdesc="Karukan Japanese IME (fcitx5) with the karukan-kz patch: commit on typing, 無変換 kana switching, shared dictionaries"
arch=('x86_64')
url="https://github.com/togatoga/karukan"
license=('MIT OR Apache-2.0')
options=('!lto')
depends=('fcitx5' 'openssl' 'oniguruma')
makedepends=('cmake' 'extra-cmake-modules' 'rust' 'libxkbcommon' 'patchelf' 'clang' 'git')
optdepends=('fcitx5-configtool: GUI configuration tool')
provides=('karukan' 'karukan-git')
conflicts=('karukan' 'karukan-git')
source=("karukan::git+https://github.com/togatoga/karukan.git"
        "karukan-kz.patch")
b2sums=('SKIP'
        '@PATCH_B2SUM@')

# The upstream commit this patch was written and tested against. When the
# patch no longer applies to the newest upstream, this commit is built.
_tested=bc3247c0549a07804a2961d44f6d75b55c416757

# Revision of the karukan-kz patch itself; it ends the package version
# (…kz9), so `pacman -Q karukan-kz-git` tells which patch is installed.
_kzrev=9

# Upstream layout, relative to the repository root
_crate="karukan-im/fcitx5"
_addondir="$_crate/fcitx5-addon"

prepare() {
    cd "$srcdir/karukan"
    if [[ ${KZ_FORCE_TESTED:-0} == 1 ]]; then
        git checkout -q "$_tested"
        git apply "$srcdir/karukan-kz.patch"
        msg2 "karukan-kz patch applied to the tested commit ${_tested:0:7} (requested)"
    elif git apply --3way "$srcdir/karukan-kz.patch"; then
        msg2 "karukan-kz patch applied to the newest upstream ($(git rev-parse --short HEAD))"
    else
        warning "the patch does not apply to the newest upstream; building the tested commit ${_tested:0:7}"
        git reset -q --hard
        git checkout -q "$_tested"
        git apply "$srcdir/karukan-kz.patch"
    fi
    rm -rf target
    cargo fetch --locked --target "$CARCH-unknown-linux-gnu"
}

pkgver() {
    cd "$srcdir/karukan"
    local desc cargo_ver=""
    if desc=$(git describe --long --abbrev=7 2>/dev/null); then
        printf '%s.kz%s' "$desc" "$_kzrev" | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
    else
        [[ -f $_crate/Cargo.toml ]] &&
            cargo_ver=$(grep -m1 '^version' "$_crate/Cargo.toml" | cut -d'"' -f2)
        printf '%sr%s.g%s.kz%s' "${cargo_ver:+$cargo_ver.}" "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)" "$_kzrev"
    fi
}

build() {
    export LLAMA_BUILD_SHARED_LIBS=1
    export RUSTONIG_SYSTEM_LIBONIG=1
    export RUSTONIG_DYNAMIC_LIBONIG=1

    cd "$srcdir/karukan/$_addondir"
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build -j"$(nproc)"

    # The dictionary tool, built with the same flags so it reuses the
    # compiled dependencies (llama.cpp included) instead of rebuilding them.
    cd "$srcdir/karukan"
    cargo build --release --locked -p karukan-cli --bin karukan-dict
}

check() {
    cd "$srcdir/karukan"
    cargo test --release --locked -p karukan-im --lib -- core::engine::tests::commit_on_input \
        core::engine::tests::user_dict_order core::engine::tests::shared_dicts \
        core::engine::tests::word_swap \
        core::engine::tests::muhenkan \
        core::engine::tests::exact_only \
        core::engine::tests::prefer \
        core::engine::prefer::tests \
        config::settings::tests::test_exact_only_defaults_and_override \
        core::engine::tests::learning::exact_learning_still_comes_first \
        core::engine::tests::learning::ctrl_delete_removes_prefix_matched_entry_by_full_reading \
        config::settings::tests::test_commit_on_input_default_and_override \
        --test-threads=1
}

package() {
    cd "$srcdir/karukan/$_addondir"
    DESTDIR="$pkgdir" cmake --install build
    local -A seen_libs=()
    local -a bundled_libs=()
    while IFS= read -r -d '' lib; do
        local base
        base="$(basename "$lib")"
        case "$base" in
            libllama*.so*|libggml*.so*)
                [[ -n ${seen_libs["$base"]+x} ]] && continue
                seen_libs["$base"]=1
                bundled_libs+=("$lib")
                ;;
        esac
    done < <(find "$srcdir/karukan/target/release/build" \
        -path '*/llama-cpp-sys-2-*/out/lib/lib*.so*' \
        \( -type f -o -type l \) -print0)

    if (( ${#bundled_libs[@]} == 0 )); then
        echo "error: could not find llama/ggml shared libraries to bundle" >&2
        return 1
    fi

    install -d "$pkgdir/usr/lib/fcitx5"
    for lib in "${bundled_libs[@]}"; do
        cp -a "$lib" "$pkgdir/usr/lib/fcitx5/"
    done

    while IFS= read -r -d '' elf; do
        patchelf --set-rpath '$ORIGIN' "$elf"
    done < <(find "$pkgdir/usr/lib/fcitx5" -maxdepth 1 -type f -name '*.so*' -print0)

    install -Dm755 "$srcdir/karukan/target/release/karukan-dict" "$pkgdir/usr/bin/karukan-dict"
    # Only if the tool links llama/ggml: point it at the bundled copies.
    if readelf -d "$pkgdir/usr/bin/karukan-dict" | grep -Eq 'NEEDED.*lib(llama|ggml)'; then
        patchelf --set-rpath /usr/lib/fcitx5 "$pkgdir/usr/bin/karukan-dict"
    fi

    install -Dm644 "$srcdir/karukan/LICENSE-MIT" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE-MIT"
    install -Dm644 "$srcdir/karukan/LICENSE-APACHE" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE-APACHE"
}
PKGBUILD_EOF
patch_b2sum=$(b2sum karukan-kz.patch | cut -d' ' -f1)
sed -i "s/@PATCH_B2SUM@/$patch_b2sum/" PKGBUILD

if [[ $mode == tested ]]; then
    export KZ_FORCE_TESTED=1
    say "動作確認済みの版（${KZ_VERSION}）にパッチを当てて作ります"
else
    say "最新の Karukan にパッチを当てて作ります（当たらなければ動作確認済みの版を使います）"
fi
say "ビルドには数分〜十数分かかります。途中で sudo のパスワードを聞かれます。"
say "「karukan-git と衝突しています。karukan-git を削除しますか？」と聞かれたら y を押してください。"

# --syncdeps: 足りないビルド用ツールを入れる / --install: できたら入れる
# --force: 同じ版でも作り直す / --clean: 作業ファイルを片付ける
makepkg --syncdeps --install --force --clean

say "インストールが終わりました: $(pacman -Q karukan-kz-git)"
# setup.sh restarts Fcitx5 itself and prints its own summary.
[[ ${KZ_FROM_SETUP:-0} == 1 ]] && exit 0
cat <<'DONE'

  次にやること: Fcitx5 を再起動して、新しい Karukan を読み込ませます。
    システム設定 → キーボード → 仮想キーボード を「なし」にして適用し、
    もう一度「Fcitx 5」に戻して適用してください。

  変換中に文字を打つと確定するようになります。元の動きに戻したいときは
  ~/.config/karukan-im/config.toml の [conversion] に
    commit_on_input = false
  と書いてください。

  Karukan を新しくしたいときは、このスクリプトをもう一度実行してください。
DONE
