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
set -euo pipefail

readonly KZ_VERSION="1854827"
readonly PATCH_SHA256="29b305be995078553454be44804203b2504564480a5100afec81dea471c2b250"
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
From 7d428cb131399fced194802d1897b0377ea02744 Mon Sep 17 00:00:00 2001
From: karukan-patch <noreply@example.invalid>
Date: Sat, 7 Nov 2026 23:12:11 +0900
Subject: [PATCH] =?UTF-8?q?karukan-kz:=20commit=5Fon=5Finput,=20=E7=84=A1?=
 =?UTF-8?q?=E5=A4=89=E6=8F=9B=20kana=20switching,=20exact-before-predictiv?=
 =?UTF-8?q?e=20ranking,=20shared=20dictionaries,=20larger=20dict=20limits,?=
 =?UTF-8?q?=20word=20swaps,=20learned-prefix=20ranking,=20exact-only=20and?=
 =?UTF-8?q?=20no-Latin=20options,=20=EF=BC=A0=20character=20lookups,=20lea?=
 =?UTF-8?q?rning=20judged=20in=20context=20(model=20scores),=20counters=20?=
 =?UTF-8?q?after=20numbers,=20far-fetched=20candidates=20dropped?=
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01QBa6wktjmCU1vbnc5GNtCs
---
 karukan-engine/src/dict.rs                    |   6 +-
 karukan-engine/src/kanji/backend.rs           |  25 +
 karukan-engine/src/kanji/llamacpp.rs          |  77 ++
 karukan-im/core/config/default.toml           |  13 +
 karukan-im/core/src/config/settings.rs        |  51 ++
 karukan-im/core/src/core/candidate.rs         |   5 +
 karukan-im/core/src/core/engine/chunk/mod.rs  |  15 +-
 karukan-im/core/src/core/engine/conversion.rs | 358 ++++++++-
 karukan-im/core/src/core/engine/init.rs       | 123 ++-
 karukan-im/core/src/core/engine/input.rs      |   5 +-
 karukan-im/core/src/core/engine/mod.rs        |  17 +-
 karukan-im/core/src/core/engine/mode.rs       |  87 +++
 karukan-im/core/src/core/engine/model.rs      |  15 +
 karukan-im/core/src/core/engine/prefer.rs     | 724 ++++++++++++++++++
 karukan-im/core/src/core/engine/swap.rs       | 192 +++++
 .../src/core/engine/tests/commit_on_input.rs  | 173 +++++
 .../core/src/core/engine/tests/exact_only.rs  | 194 +++++
 .../core/src/core/engine/tests/learning.rs    |  40 +
 karukan-im/core/src/core/engine/tests/mod.rs  |  11 +-
 .../core/src/core/engine/tests/muhenkan.rs    | 128 ++++
 .../core/src/core/engine/tests/prefer.rs      | 453 +++++++++++
 .../core/src/core/engine/tests/rewriter.rs    |   2 +-
 .../src/core/engine/tests/shared_dicts.rs     |  75 ++
 .../src/core/engine/tests/user_dict_order.rs  |  78 ++
 .../core/src/core/engine/tests/word_swap.rs   |  61 ++
 karukan-im/core/src/core/engine/types.rs      |  28 +-
 karukan-im/core/src/core/keycode.rs           |   2 +
 27 files changed, 2886 insertions(+), 72 deletions(-)
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
index 957905d..f9a5d26 100644
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
index 6fa1a27..7666da8 100644
--- a/karukan-engine/src/kanji/backend.rs
+++ b/karukan-engine/src/kanji/backend.rs
@@ -148,6 +148,31 @@ impl KanaKanjiConverter {
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
index 5b39643..8055c3e 100644
--- a/karukan-engine/src/kanji/llamacpp.rs
+++ b/karukan-engine/src/kanji/llamacpp.rs
@@ -789,6 +789,83 @@ impl LlamaCppModel {
         Ok(generated)
     }
 
+    /// Log-probability the model gives each of `continuations` (plus the
+    /// end-of-output token) as the text following `prompt`: forced decoding.
+    /// The prompt is evaluated once and its KV cache shared by every
+    /// continuation, so each one costs only its own few tokens. Higher is
+    /// likelier; values are comparable between continuations of one prompt.
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
+        let mut ctx = self.new_context(
+            self.context_params_with_n_ctx(n_ctx)
+                .with_n_seq_max(n_seq.try_into().unwrap_or(u32::MAX))
+                .with_n_batch(batch_cap as u32)
+                .with_n_ubatch(batch_cap as u32),
+        )?;
+        let vocab_size = self.model.n_vocab() as usize;
+        let eos = self.model.vocab().eos();
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
+        // Every continuation in its own sequence on top of the shared prompt.
+        batch.clear();
+        let mut rows: Vec<(usize, LlamaToken)> = Vec::with_capacity(total);
+        for (k, continuation) in continuations.iter().enumerate() {
+            if continuation.is_empty() {
+                continue;
+            }
+            let seq = (k + 1) as i32;
+            ctx.copy_kv_cache_seq(0, seq, None, None)
+                .map_err(inference_err)?;
+            for (j, &token) in continuation.iter().enumerate() {
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
         self.model.vocab().eos()
diff --git a/karukan-im/core/config/default.toml b/karukan-im/core/config/default.toml
index 8199f02..9f08d36 100644
--- a/karukan-im/core/config/default.toml
+++ b/karukan-im/core/config/default.toml
@@ -49,6 +49,19 @@ light_model = "jinen-v2-xsmall-q5"
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
 # ユーザー辞書: ~/.local/share/karukan-im/user_dicts/ に辞書ファイルを配置（Mozc TSV or KRKN binary）
 
 # 変換モデル。model / light_model はここのキーを参照する。値は 2 通り:
diff --git a/karukan-im/core/src/config/settings.rs b/karukan-im/core/src/config/settings.rs
index b54c333..c977e4c 100644
--- a/karukan-im/core/src/config/settings.rs
+++ b/karukan-im/core/src/config/settings.rs
@@ -201,6 +201,18 @@ pub struct ConversionSettings {
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
 }
 
 /// Learning cache settings
@@ -561,6 +573,45 @@ use_context = false
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
index b46e39b..c78c111 100644
--- a/karukan-im/core/src/core/engine/chunk/mod.rs
+++ b/karukan-im/core/src/core/engine/chunk/mod.rs
@@ -127,7 +127,20 @@ impl InputMethodEngine {
     ) -> ComposingChunk {
         let converted = if reading.chars().any(is_japanese) {
             let lctx = self.lctx_for(base_ctx, combined);
-            self.convert_chunk(&reading, &lctx)
+            let converted = self.convert_chunk(&reading, &lctx);
+            // What was learned, where the context allows it: the whole
+            // chunk, or a word inside it (see `prefer`).
+            let converted = self.apply_preferences(&reading, &lctx, converted);
+            // `alphabet_candidates = false`: kana typed as るる must not
+            // turn into lulu on screen; leave it as typed instead.
+            if !self.config.alphabet_candidates
+                && super::conversion::is_unwanted_latin(&reading, &converted)
+                && !super::conversion::is_latin_only(&reading)
+            {
+                reading.clone()
+            } else {
+                converted
+            }
         } else {
             reading.clone()
         };
diff --git a/karukan-im/core/src/core/engine/conversion.rs b/karukan-im/core/src/core/engine/conversion.rs
index 61f8714..8df1642 100644
--- a/karukan-im/core/src/core/engine/conversion.rs
+++ b/karukan-im/core/src/core/engine/conversion.rs
@@ -31,6 +31,72 @@ enum TailConstraint {
     Dead,
 }
 
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
@@ -124,6 +190,16 @@ impl InputMethodEngine {
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
@@ -207,6 +283,14 @@ impl InputMethodEngine {
         .collect::<Vec<_>>();
         let mut candidates = Vec::new();
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
@@ -222,7 +306,7 @@ impl InputMethodEngine {
                 if candidates.len() >= limit {
                     break;
                 }
-                if seen.insert(cand.surface.clone()) {
+                if wanted(&cand.surface) && seen.insert(cand.surface.clone()) {
                     candidates.push(AnnotatedCandidate::new(cand.surface.clone(), source));
                 }
             }
@@ -233,7 +317,8 @@ impl InputMethodEngine {
         // rides on the candidate so selecting it commits and records under
         // the right key.
         let constraint = self.tail_constraint(pending);
-        if reading.chars().count() >= min_prefix_chars
+        if self.config.prediction
+            && reading.chars().count() >= min_prefix_chars
             && !matches!(constraint, TailConstraint::Dead)
         {
             let mut budget = predictive_limit;
@@ -253,7 +338,7 @@ impl InputMethodEngine {
                     if budget == 0 || candidates.len() >= limit {
                         break;
                     }
-                    if seen.insert(m.candidate.surface.clone()) {
+                    if wanted(&m.candidate.surface) && seen.insert(m.candidate.surface.clone()) {
                         budget -= 1;
                         candidates.push(
                             AnnotatedCandidate::new(m.candidate.surface.clone(), source)
@@ -297,27 +382,97 @@ impl InputMethodEngine {
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
         // Priority: Learning → User Dictionary → Model → System Dictionary → Fallback
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
 
         // 2. User dictionary candidates (system dictionary follows the model
         //    in step 4, so the two are split here).
@@ -332,11 +487,68 @@ impl InputMethodEngine {
             )
             .into_iter()
             .partition(|ac| ac.source == CandidateSource::UserDictionary);
-        for ac in user_dict {
+        // Only exact user-dictionary matches outrank the model, and every
+        // exact match comes before any predictive one (a reading extending
+        // the typed one). With a large user dictionary, predictive entries
+        // would otherwise take the top slot for any short reading (さと +
+        // Space → 悟 instead of 里) and push the system dictionary's exact
+        // matches off the first page.
+        let (user_exact, user_predictive): (Vec<_>, Vec<_>) =
+            user_dict.into_iter().partition(|ac| ac.reading.is_none());
+        let (system_exact, system_predictive): (Vec<_>, Vec<_>) =
+            system_dict.into_iter().partition(|ac| ac.reading.is_none());
+        for ac in user_exact {
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
+        candidates.retain(|t| !(drop_latin && is_unwanted_latin(reading, t)));
+        // The other beams and the swaps are judged together by the main
+        // model: its likeliest first, and nothing it finds far-fetched next
+        // to its best answer (耳が主基です, で着ていない, その足袋に).
+        let swap_texts: HashSet<String> = swaps.iter().cloned().collect();
+        if let Some(best) = candidates.first().cloned() {
+            let mut rest = candidates.split_off(1);
+            for text in swaps {
+                if text != best && !rest.contains(&text) {
+                    rest.push(text);
+                }
+            }
+            candidates.extend(self.rank_by_model(&prefix, &span, &span_lctx, &best, rest));
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
         if candidates.is_empty() {
             // No literal fallback in emoji mode: `:smile` must not outrank
             // the 😄 surfaced by the rewriter step below.
@@ -348,12 +560,24 @@ impl InputMethodEngine {
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
 
-        // 4. System dictionary candidates
-        for ac in system_dict {
+        // 4. Exact system dictionary candidates, then the predictive ones
+        //    (learned ones first, then the user dictionary, as among the exact
+        //    matches)
+        for ac in system_exact
+            .into_iter()
+            .chain(learned_predictive)
+            .chain(user_predictive)
+            .chain(system_predictive)
+        {
             builder.push(ac);
         }
 
@@ -446,7 +670,11 @@ impl InputMethodEngine {
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
@@ -650,10 +878,14 @@ impl InputMethodEngine {
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
 
@@ -665,6 +897,57 @@ impl InputMethodEngine {
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
@@ -737,11 +1020,27 @@ impl InputMethodEngine {
     /// buffer is a `:query`, not a kana reading, and would corrupt the
     /// kana-keyed cache.
     pub(super) fn record_learning(&mut self, reading: &str, surface: &str) {
+        self.learn(reading, surface, true);
+    }
+
+    /// A commit nobody chose — Enter on the live conversion, a focus-out —
+    /// is the engine's own answer coming back, not a preference: learning
+    /// it only fills the history with sentences and bare kana (が → が).
+    /// It refreshes an entry that is already there and never adds one.
+    pub(super) fn record_unchosen(&mut self, reading: &str, surface: &str) {
+        self.learn(reading, surface, false);
+    }
+
+    fn learn(&mut self, reading: &str, surface: &str, create: bool) {
         if self.mode.current() == InputMode::Emoji {
             return;
         }
-        if let Some(cache) = &mut self.learning {
-            cache.record(reading, surface);
+        let lctx = self.truncate_context_for_api();
+        let (key, surface) = prefer::learning_key(reading, surface, &lctx);
+        if let Some(cache) = &mut self.learning
+            && (create || cache.lookup(&key).iter().any(|(s, _)| *s == surface))
+        {
+            cache.record(&key, &surface);
         }
     }
 
@@ -800,10 +1099,17 @@ impl InputMethodEngine {
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
diff --git a/karukan-im/core/src/core/engine/init.rs b/karukan-im/core/src/core/engine/init.rs
index addd840..9dafaab 100644
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
@@ -189,15 +191,18 @@ impl InputMethodEngine {
             return;
         }
 
-        match Dictionary::load(&path) {
-            Ok(dict) => {
-                debug!("System dictionary loaded from {:?}", path);
-                self.dicts.system = Some(dict);
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
@@ -282,36 +287,84 @@ impl InputMethodEngine {
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
 
-        match Dictionary::merge(dicts) {
-            Ok(Some(merged)) => {
-                debug!(
-                    "User dictionaries merged successfully ({} files from {:?})",
-                    paths.len(),
-                    dir
-                );
-                self.dicts.user = Some(merged);
-            }
-            Ok(None) => {}
-            Err(e) => {
-                debug!("Failed to merge user dictionaries: {}", e);
-            }
-        }
+fn file_stamp(path: &Path) -> FileStamp {
+    let meta = std::fs::metadata(path).ok();
+    (
+        path.to_path_buf(),
+        meta.as_ref().and_then(|m| m.modified().ok()),
+        meta.map_or(0, |m| m.len()),
+    )
+}
+
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
index a046768..5ca1b28 100644
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
@@ -399,7 +402,7 @@ impl InputMethodEngine {
                 .with_action(EngineAction::HideAuxText);
         }
 
-        self.record_learning(&reading, &text);
+        self.record_unchosen(&reading, &text);
         self.end_composition();
 
         // HideCandidates is required here: the auto-suggest/live-conversion
diff --git a/karukan-im/core/src/core/engine/mod.rs b/karukan-im/core/src/core/engine/mod.rs
index 6c6179e..36bc30a 100644
--- a/karukan-im/core/src/core/engine/mod.rs
+++ b/karukan-im/core/src/core/engine/mod.rs
@@ -14,7 +14,9 @@ mod input;
 mod input_buffer;
 mod mode;
 mod model;
+mod prefer;
 mod strategy;
+mod swap;
 mod types;
 
 pub use types::*;
@@ -146,6 +148,9 @@ pub struct InputMethodEngine {
     /// LRU cache of model conversion results keyed by reading + lctx +
     /// strategy. Content-addressed, so it survives commits and resets.
     conversion_cache: ConversionCache,
+    /// Model log-probabilities already computed (see `prefer`): what the
+    /// model thinks of a surface it did not necessarily propose.
+    score_cache: prefer::ScoreCache,
     /// Suppresses the auto-suggest model call while a conversion detours
     /// through the composing path and throws the render away. Owned by
     /// `in_composing`, which sets and clears it around the one call.
@@ -186,6 +191,7 @@ impl InputMethodEngine {
             chunks: Vec::new(),
             chunk_breaks: Vec::new(),
             conversion_cache: ConversionCache::default(),
+            score_cache: prefer::ScoreCache::default(),
             suppress_suggest: false,
             shown_suggestions: CandidateList::default(),
             dicts: Dictionaries::default(),
@@ -619,6 +625,15 @@ impl InputMethodEngine {
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
@@ -701,7 +716,7 @@ impl InputMethodEngine {
             InputState::Empty => String::new(),
             InputState::Composing { .. } => {
                 let (reading, text) = self.resolve_composing_commit();
-                self.record_learning(&reading, &text);
+                self.record_unchosen(&reading, &text);
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
index d509d60..5294b9a 100644
--- a/karukan-im/core/src/core/engine/model.rs
+++ b/karukan-im/core/src/core/engine/model.rs
@@ -279,6 +279,21 @@ impl InputMethodEngine {
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
index 0000000..9c38d3a
--- /dev/null
+++ b/karukan-im/core/src/core/engine/prefer.rs
@@ -0,0 +1,724 @@
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
+        self.run_kana_kanji_conversion(reading, api_context, 1)
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
+            .lookup(reading)
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
+        // Judging a word inside a sentence is one more model pass per
+        // keystroke: where live conversion has fallen back to the light
+        // model for speed, the light model judges too.
+        let judge =
+            if self.metrics.adaptive_use_light_model && self.converters.light_kanji.is_some() {
+                ModelRole::Light
+            } else {
+                ModelRole::Main
+            };
+        self.respell_sentence(reading, lctx, &model, true, judge)
+            .accepted
+            .unwrap_or(model)
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
+            if let Some((out, _)) =
+                self.replace_aligned(&r, 0, len, &word, &counter.surface, sentence)
+            {
+                return Some(out);
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
+                    if let Some((surface, score)) = cache.lookup(&word).into_iter().next() {
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
+            let Some((candidate, kana)) =
+                self.replace_aligned(&r, start, len, &word, &learned, &current)
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
+    /// `sentence` with the word read `word` at `r[start..start + len]`
+    /// respelled as `learned`, when that word can be located for certain,
+    /// and whether the sentence had left it in hiragana.
+    fn replace_aligned(
+        &self,
+        r: &[char],
+        start: usize,
+        len: usize,
+        word: &str,
+        learned: &str,
+        sentence: &str,
+    ) -> Option<(String, bool)> {
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
+                    starts_a_word(before, &w, true)
+                } else {
+                    stands_alone(before, &w, after)
+                };
+                if alone && aligns(before, &r[..start]) && aligns(after, &r[start + len..]) {
+                    let mut out: String = before.iter().collect();
+                    out.push_str(learned);
+                    out.extend(after.iter());
+                    return Some((out, kana));
+                }
+            }
+        }
+        None
+    }
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
+enum Script {
+    Hira,
+    Kata,
+    Kanji,
+    Other,
+}
+
+fn script(c: char) -> Script {
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
+        (Script::Hira, Script::Hira) => {
+            after_particle
+                && matches!(
+                    prev,
+                    'は' | 'が' | 'を' | 'に' | 'で' | 'と' | 'も' | 'の' | 'へ'
+                )
+        }
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
+fn aligns(text: &[char], reading: &[char]) -> bool {
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
index 0000000..d712625
--- /dev/null
+++ b/karukan-im/core/src/core/engine/swap.rs
@@ -0,0 +1,192 @@
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
+    /// `texts` — respellings of `best`, the model's conversion of the
+    /// reading that `prefix` and `span` make up — in the order the model
+    /// finds them likely after `lctx`, without those it finds far-fetched
+    /// next to `best`. Unchanged when no model can say.
+    pub(super) fn rank_by_model(
+        &mut self,
+        prefix: &str,
+        span: &str,
+        lctx: &str,
+        best: &str,
+        texts: Vec<String>,
+    ) -> Vec<String> {
+        let tails: Option<Vec<&str>> = std::iter::once(best)
+            .chain(texts.iter().map(String::as_str))
+            .map(|t| t.strip_prefix(prefix))
+            .collect();
+        let Some(tails) = tails.filter(|_| !texts.is_empty() && !span.is_empty()) else {
+            return texts;
+        };
+        let Some(scores) = self.model_scores(span, lctx, &tails) else {
+            return texts;
+        };
+        let floor = scores[0] - prefer::SWAP_GAP_MAX;
+        let mut ranked: Vec<(f32, String)> = scores[1..]
+            .iter()
+            .copied()
+            .zip(texts)
+            .filter(|(score, _)| *score >= floor)
+            .collect();
+        ranked.sort_by(|a, b| b.0.total_cmp(&a.0));
+        ranked.into_iter().map(|(_, text)| text).collect()
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
+fn is_word(surface: &str) -> bool {
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
index 098ad3e..47411b5 100644
--- a/karukan-im/core/src/core/engine/tests/mod.rs
+++ b/karukan-im/core/src/core/engine/tests/mod.rs
@@ -10,24 +10,31 @@ mod basic;
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
@@ -58,12 +65,12 @@ fn seed_model_cache(engine: &mut InputMethodEngine, katakana: &str, lctx: &str,
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
diff --git a/karukan-im/core/src/core/engine/tests/prefer.rs b/karukan-im/core/src/core/engine/tests/prefer.rs
new file mode 100644
index 0000000..c0b164b
--- /dev/null
+++ b/karukan-im/core/src/core/engine/tests/prefer.rs
@@ -0,0 +1,453 @@
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
+        &[("その旅に", -0.6), ("その足袋に", -9.0), ("その度に", -0.5)],
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
diff --git a/karukan-im/core/src/core/engine/tests/rewriter.rs b/karukan-im/core/src/core/engine/tests/rewriter.rs
index f0a85c5..8ba85d0 100644
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
index 0f9ba86..80dc465 100644
--- a/karukan-im/core/src/core/engine/types.rs
+++ b/karukan-im/core/src/core/engine/types.rs
@@ -107,6 +107,15 @@ pub struct EngineConfig {
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
     /// When the candidate window (aux line included) opens
     pub candidate_window: CandidateWindow,
     /// Which symbol the `,` `.` `/` `[` `]` keys type
@@ -142,6 +151,9 @@ impl EngineConfig {
             strategy: settings.conversion.strategy,
             verbose: settings.display.verbose,
             live_conversion: settings.conversion.live_conversion,
+            commit_on_input: settings.conversion.commit_on_input,
+            prediction: settings.conversion.prediction,
+            alphabet_candidates: settings.conversion.alphabet_candidates,
             candidate_window: settings.display.candidate_window,
             symbol: settings.symbol.style(),
             width: settings.width,
@@ -168,6 +180,13 @@ impl Default for EngineConfig {
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
             candidate_window: CandidateWindow::default(),
             symbol: SymbolStyle::default(),
             width: WidthRules::default(),
@@ -305,13 +324,16 @@ impl LiveConversion {
     }
 }
 
-/// Dictionary store: system, user, and future cache dictionaries
+/// Dictionary store: system, user, and future cache dictionaries.
+///
+/// Both are shared (`Arc`): fcitx5 runs one engine per input context, and
+/// `init.rs` hands every engine in the process the same loaded copy.
 #[derive(Default)]
 pub(in crate::core) struct Dictionaries {
     /// System dictionary for yada double-array trie lookup
-    pub system: Option<Dictionary>,
+    pub system: Option<std::sync::Arc<Dictionary>>,
     /// User dictionary (merged from user_dict_paths)
-    pub user: Option<Dictionary>,
+    pub user: Option<std::sync::Arc<Dictionary>>,
 }
 
 /// Conversion model dispatch strategy based on input length
diff --git a/karukan-im/core/src/core/keycode.rs b/karukan-im/core/src/core/keycode.rs
index 2831fbd..2dcd908 100644
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
_tested=185482700749fd15e58555c331b4e01ce5257344

# Revision of the karukan-kz patch itself; it ends the package version
# (…kz6), so `pacman -Q karukan-kz-git` tells which patch is installed.
_kzrev=6

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
