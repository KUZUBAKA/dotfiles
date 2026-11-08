#!/usr/bin/env bash
# setup.sh — パッチ入り Karukan と辞書を、まとめて全部そろえる
#
# 使い方:
#   bash setup.sh                  足りないものを入れ、辞書を作って登録し、Fcitx5 を再起動する
#   bash setup.sh --update         Karukan も最新版（パッチ入り）に入れ直してから同じことをする
#   bash setup.sh --refresh        公式のシステム辞書をダウンロードし直してから同じことをする
#   bash setup.sh --my-dict PATH   自分の辞書（標準: ~/dotfiles/KDE-IME.txt）の場所を指定する
#
# やること:
#   1. パッチ入り Karukan（karukan-kz-git）が無ければ入れる
#   2. 公式のシステム辞書に追加の言葉を足して dict.bin を作る（材料が同じなら作り直さない）
#   3. dict.bin と、ユーザー辞書の txt を ~/.local/share/karukan-im/ に登録する
#      （自分の辞書は 00-KDE-IME.txt という名前のシンボリックリンクにする）
#   4. 登録した辞書が読めるか確かめて、Fcitx5 を再起動する
set -euo pipefail

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> 注意:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> エラー:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly HERE
readonly DATA="${XDG_DATA_HOME:-$HOME/.local/share}/karukan-im"
readonly USER_DICTS="$DATA/user_dicts"
readonly OFFICIAL_URL="https://github.com/togatoga/karukan/releases/latest/download/dict.tgz"
# The files this package puts into user_dicts (also removed as .bin, from
# the earlier build-dict.sh, so nothing is loaded twice).
readonly OUR_DICTS=(10-bluearchive 11-jujutsukaisen 12-touhou 13-nichijo 20-yojijukugo)

update=0
refresh=0
my_dict="${KARUKAN_MY_DICT:-$HOME/dotfiles/KDE-IME.txt}"
while (( $# )); do
    case "$1" in
        --update) update=1 ;;
        --refresh) refresh=1 ;;
        --my-dict) [[ $# -ge 2 ]] || die "--my-dict の後に辞書のパスを書いてください"; my_dict="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; die "知らないオプションです: $1" ;;
    esac
    shift
done

(( EUID != 0 )) || die "root（sudo）では実行しないでください。普段のユーザーのまま実行してください。"
command -v pacman >/dev/null || die "pacman が見つかりません。Arch 系（CachyOS など）専用のスクリプトです。"
cd "$HERE"

# --- 1. 必要な道具 -----------------------------------------------------------
missing=()
for pair in curl:curl tar:tar python3:python sha256sum:coreutils; do
    command -v "${pair%%:*}" >/dev/null || missing+=("${pair#*:}")
done
if (( ${#missing[@]} )); then
    say "足りない道具を入れます: ${missing[*]}（sudo のパスワードを聞かれます）"
    sudo pacman -S --needed "${missing[@]}"
fi

# --- 2. パッチ入り Karukan ----------------------------------------------------
if (( update )) || ! pacman -Q karukan-kz-git >/dev/null 2>&1; then
    say "パッチ入りの Karukan を入れます"
    KZ_FROM_SETUP=1 bash "$HERE/karukan-kz-install.sh"
fi
pacman -Q karukan-kz-git >/dev/null 2>&1 || die "karukan-kz-git が入っていません。上のエラーを確かめてください。"
command -v karukan-dict >/dev/null || die "karukan-dict が見つかりません。bash setup.sh --update で入れ直してください。"
say "Karukan: $(pacman -Q karukan-kz-git)"

# --- 3. システム辞書を作る -----------------------------------------------------
mkdir -p cache out
avail_mb=$(df --output=avail -BM "$HERE" | tail -1 | tr -dc '0-9')
(( avail_mb >= 2000 )) || die "空き容量が足りません（${avail_mb}MB）。2GB 以上空けてから実行してください。"

if (( refresh )) || [[ ! -f cache/dict.bin ]]; then
    say "公式のシステム辞書をダウンロードしています（約74MB）"
    curl -fL --retry 3 -o cache/dict.tgz "$OFFICIAL_URL"
    tar -xzf cache/dict.tgz -C cache dict.bin
    rm -f cache/dict.tgz
fi
[[ $(head -c 4 cache/dict.bin) == KRKN ]] || die "ダウンロードした辞書が壊れています。bash setup.sh --refresh でやり直してください。"

# Rebuild only when an input (or the dictionary tool) changed.
stamp=$( { sha256sum cache/dict.bin system/top.tsv system/additions.tsv.xz tools/merge_system_dict.py
           pacman -Q karukan-kz-git; } | sha256sum | cut -d' ' -f1 )
if [[ -f out/dict.bin && -f out/dict.stamp && $(<out/dict.stamp) == "$stamp" ]]; then
    say "システム辞書は作成済みです（材料が変わっていないので作り直しません）"
else
    say "システム辞書を組み立てています（1〜2分かかります）"
    rm -f out/dict.stamp
    python3 tools/merge_system_dict.py cache/dict.bin system/top.tsv system/additions.tsv.xz cache/merged.json
    karukan-dict build cache/merged.json -o out/dict.bin.new >/dev/null
    rm -f cache/merged.json
    mv -f out/dict.bin.new out/dict.bin
    printf '%s\n' "$stamp" > out/dict.stamp
fi

# --- 4. 登録する ---------------------------------------------------------------
say "辞書を登録しています: $DATA"
mkdir -p "$USER_DICTS"
# Keep whatever system dictionary was there before, once.
if [[ -f $DATA/dict.bin && ! -f $DATA/dict.bin.orig && ! -f $DATA/.karukan-kz ]]; then
    mv "$DATA/dict.bin" "$DATA/dict.bin.orig"
    say "前からあったシステム辞書は dict.bin.orig という名前で残しました"
fi
# Copy then rename, so a running Fcitx5 never sees a half-written file.
cp out/dict.bin "$DATA/dict.bin.new"
mv -f "$DATA/dict.bin.new" "$DATA/dict.bin"
printf '%s\n' "$stamp" > "$DATA/.karukan-kz"

for name in "${OUR_DICTS[@]}"; do
    rm -f "$USER_DICTS/$name.bin" "$USER_DICTS/$name.txt"
    cp "user_dicts/$name.txt" "$USER_DICTS/$name.txt"
done
if [[ -f $my_dict ]]; then
    ln -sfn "$(readlink -f "$my_dict")" "$USER_DICTS/00-KDE-IME.txt"
    say "あなたの辞書をつなぎました: 00-KDE-IME.txt → $(readlink -f "$my_dict")"
else
    warn "あなたの辞書が見つかりませんでした: $my_dict（--my-dict で場所を指定できます）"
fi
for f in "$USER_DICTS"/*KDE-IME-expanded*; do
    [[ -e $f ]] && warn "$(basename "$f") は中身がこの辞書に入っているので、user_dicts から外してください。"
done

# --- 5. 読めるか確かめる -------------------------------------------------------
check=$(karukan-dict view "$DATA/dict.bin" -q ごじょう 2>/dev/null) || true
[[ $check == *五条悟* ]] || die "登録したシステム辞書を読めませんでした。"
check=$(karukan-dict view "$USER_DICTS"/*.txt -q ごじょうさとる 2>/dev/null) || true
[[ $check == *五条悟* ]] || die "登録したユーザー辞書を読めませんでした。"
say "辞書の読み込みを確かめました（ごじょう → 五条悟 など）"

# --- 6. Fcitx5 を再起動する ----------------------------------------------------
# On Plasma (Wayland) KWin launches Fcitx5 from the virtual keyboard setting
# (kwinrc [Wayland] InputMethod) and stops/starts it when that setting
# changes — exactly what toggling it in System Settings does.
im=""
if [[ ${XDG_SESSION_TYPE:-} == wayland ]] && command -v kreadconfig6 >/dev/null && command -v kwriteconfig6 >/dev/null; then
    im=$(kreadconfig6 --file kwinrc --group Wayland --key InputMethod)
fi
if [[ -n $im ]]; then
    say "Fcitx5 を再起動しています"
    restore_im() { kwriteconfig6 --file kwinrc --group Wayland --key InputMethod --type path --notify "$im"; }
    trap restore_im EXIT INT TERM
    kwriteconfig6 --file kwinrc --group Wayland --key InputMethod --delete --notify
    for _ in {1..20}; do pgrep -x fcitx5 >/dev/null || break; sleep 0.5; done
    restore_im
    trap - EXIT INT TERM
    started=0
    for _ in {1..20}; do pgrep -x fcitx5 >/dev/null && { started=1; break; }; sleep 0.5; done
    if (( started )); then
        say "Fcitx5 を再起動しました"
    else
        warn "Fcitx5 が起動していません。システム設定 → キーボード → 仮想キーボード で「Fcitx 5」を選び直してください。"
    fi
else
    warn "自動で再起動できない環境でした。システム設定 → キーボード → 仮想キーボード を「なし」にして適用し、「Fcitx 5」に戻して適用してください。"
fi

cat <<DONE

  完了しました。最初の1文字を打つときだけ、辞書の読み込みで少し待ちます。

  登録した場所: $DATA
    dict.bin                 システム辞書
    user_dicts/*.txt         ユーザー辞書（txt なので、そのまま書き換えられます）
    user_dicts/00-KDE-IME.txt  あなたの辞書（dotfiles の本体につながっています）

  txt を書き換えたら Fcitx5 を再起動すると反映されます（bash setup.sh をもう一度実行しても同じです）。
DONE
