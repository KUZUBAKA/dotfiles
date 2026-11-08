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
set -euo pipefail

readonly KZ_VERSION="1854827"
readonly PATCH_SHA256="9ba5ff33a4130a7f57170939d90fc658b549fd863485320defcb064b2a2cd79f"
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
diff --git a/karukan-im/core/config/default.toml b/karukan-im/core/config/default.toml
index 8199f02..f936827 100644
--- a/karukan-im/core/config/default.toml
+++ b/karukan-im/core/config/default.toml
@@ -49,6 +49,12 @@ light_model = "jinen-v2-xsmall-q5"
 n_threads = 4
 # 起動時にライブ変換を有効にする（Ctrl+Shift+L で実行中も切替可能）
 live_conversion = true
+# 変換中（Space で候補を選んでいる間）に文字キーを押したときの動き。
+#   true : 選択中の候補を確定し、押した文字から次の入力を始める（MS-IME / Mozc と同じ）
+#   false: 確定せずに読みを伸ばして変換し直す（Karukan 本来の動き）
+# Ctrl+T / Ctrl+R / Ctrl+I で候補を絞り込んでいる間と絵文字入力中は、検索なので
+# どちらの設定でも読みを伸ばす。
+commit_on_input = true
 # ユーザー辞書: ~/.local/share/karukan-im/user_dicts/ に辞書ファイルを配置（Mozc TSV or KRKN binary）
 
 # 変換モデル。model / light_model はここのキーを参照する。値は 2 通り:
diff --git a/karukan-im/core/src/config/settings.rs b/karukan-im/core/src/config/settings.rs
index b54c333..02f5186 100644
--- a/karukan-im/core/src/config/settings.rs
+++ b/karukan-im/core/src/config/settings.rs
@@ -201,6 +201,11 @@ pub struct ConversionSettings {
     pub n_threads: u32,
     /// Enable live conversion at startup (Ctrl+Shift+L still toggles at runtime)
     pub live_conversion: bool,
+    /// A printable keystroke during an unfiltered conversion commits the
+    /// selection and starts the next composition with it (MS-IME / mozc
+    /// style). `false` keeps the refine-in-place behaviour. Narrowed source
+    /// views and the emoji picker always refine.
+    pub commit_on_input: bool,
 }
 
 /// Learning cache settings
@@ -561,6 +566,25 @@ use_context = false
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
diff --git a/karukan-im/core/src/core/engine/conversion.rs b/karukan-im/core/src/core/engine/conversion.rs
index 61f8714..10ea866 100644
--- a/karukan-im/core/src/core/engine/conversion.rs
+++ b/karukan-im/core/src/core/engine/conversion.rs
@@ -332,7 +332,17 @@ impl InputMethodEngine {
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
 
@@ -352,8 +362,13 @@ impl InputMethodEngine {
             }
         }
 
-        // 4. System dictionary candidates
-        for ac in system_dict {
+        // 4. Exact system dictionary candidates, then the predictive ones
+        //    (user dictionary first, as among the exact matches)
+        for ac in system_exact
+            .into_iter()
+            .chain(user_predictive)
+            .chain(system_predictive)
+        {
             builder.push(ac);
         }
 
@@ -650,10 +665,14 @@ impl InputMethodEngine {
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
 
@@ -665,6 +684,57 @@ impl InputMethodEngine {
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
diff --git a/karukan-im/core/src/core/engine/mod.rs b/karukan-im/core/src/core/engine/mod.rs
index 6c6179e..b4b3369 100644
--- a/karukan-im/core/src/core/engine/mod.rs
+++ b/karukan-im/core/src/core/engine/mod.rs
@@ -619,6 +619,15 @@ impl InputMethodEngine {
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
diff --git a/karukan-im/core/src/core/engine/tests/mod.rs b/karukan-im/core/src/core/engine/tests/mod.rs
index 098ad3e..a50b0cc 100644
--- a/karukan-im/core/src/core/engine/tests/mod.rs
+++ b/karukan-im/core/src/core/engine/tests/mod.rs
@@ -10,6 +10,7 @@ mod basic;
 mod candidate_window;
 mod candidates;
 mod chunks;
+mod commit_on_input;
 mod conversion;
 mod cursor;
 mod date;
@@ -18,15 +19,18 @@ mod katakana;
 mod learning;
 mod live_conversion;
 mod mode_toggle;
+mod muhenkan;
 mod passthrough;
 mod pending_romaji;
 mod persona;
 mod predictive;
 mod rewriter;
+mod shared_dicts;
 mod single_kanji;
 mod source_filter;
 mod strategy;
 mod surrounding;
+mod user_dict_order;
 mod width;
 
 /// Engine seeded with a learning entry `reading → surface`, no kanji model.
@@ -58,12 +62,12 @@ fn seed_model_cache(engine: &mut InputMethodEngine, katakana: &str, lctx: &str,
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
diff --git a/karukan-im/core/src/core/engine/types.rs b/karukan-im/core/src/core/engine/types.rs
index 0f9ba86..aa386ee 100644
--- a/karukan-im/core/src/core/engine/types.rs
+++ b/karukan-im/core/src/core/engine/types.rs
@@ -107,6 +107,10 @@ pub struct EngineConfig {
     pub verbose: bool,
     /// Whether live conversion is enabled at engine startup
     pub live_conversion: bool,
+    /// Whether a printable keystroke during an unfiltered conversion commits
+    /// the selection and starts the next composition (MS-IME / mozc style)
+    /// instead of refining the reading in place
+    pub commit_on_input: bool,
     /// When the candidate window (aux line included) opens
     pub candidate_window: CandidateWindow,
     /// Which symbol the `,` `.` `/` `[` `]` keys type
@@ -142,6 +146,7 @@ impl EngineConfig {
             strategy: settings.conversion.strategy,
             verbose: settings.display.verbose,
             live_conversion: settings.conversion.live_conversion,
+            commit_on_input: settings.conversion.commit_on_input,
             candidate_window: settings.display.candidate_window,
             symbol: settings.symbol.style(),
             width: settings.width,
@@ -168,6 +173,9 @@ impl Default for EngineConfig {
             strategy: StrategyMode::default(),
             verbose: false,
             live_conversion: false,
+            // The engine default keeps the refine-in-place behaviour; the
+            // shipped config.toml default (default.toml) turns it on.
+            commit_on_input: false,
             candidate_window: CandidateWindow::default(),
             symbol: SymbolStyle::default(),
             width: WidthRules::default(),
@@ -305,13 +313,16 @@ impl LiveConversion {
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
        printf '%s.kz' "$desc" | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
    else
        [[ -f $_crate/Cargo.toml ]] &&
            cargo_ver=$(grep -m1 '^version' "$_crate/Cargo.toml" | cut -d'"' -f2)
        printf '%sr%s.g%s.kz' "${cargo_ver:+$cargo_ver.}" "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
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
        core::engine::tests::muhenkan \
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
