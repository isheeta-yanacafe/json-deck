#!/usr/bin/env bash
set -uo pipefail

# okaeri.sh
# 個人用のWIP同期スクリプト。別端末（Mac A）でodekake.shにより退避された
# WIPコードを、このMacの現在のブランチに未コミットの変更として取り込む。
#
# 衝突なく受け取れた場合は、受け取った内容"だけ"を自動でコミット・pushする
# （このマシン側で元から未コミットだった変更＝stashした分には一切触れない）。
# 衝突が発生した場合（cherry-pick失敗、または受信内容とこのマシン側の
# 未コミット変更が同じファイルに触れる場合）は、これまで通り処理を止めて
# 人間の判断を待つ（自動でのマージ解消・pushは一切行わない）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${REPO_ROOT}/scripts/logs"
LOG_FILE="${LOG_DIR}/sync.log"
ERR_LOG_FILE="${LOG_DIR}/sync.error.log"
REMOTE_BRANCH="wip-warp-scratch"

mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${ERR_LOG_FILE}"
}

cd "${REPO_ROOT}" || { err "リポジトリルートへの移動に失敗しました: ${REPO_ROOT}"; exit 1; }

log "okaeri.sh を開始します。"

STASHED=0
STASH_FILES_LIST_FILE="$(mktemp)"

if ! git diff --quiet || ! git diff --cached --quiet; then
    log "未コミットの変更（ステージ済み/未ステージ）を検出したため、stash に退避します。"
    STASH_MSG="okaeri.sh: auto stash $(date '+%Y-%m-%d %H:%M:%S')"
    if ! git stash push -u -m "${STASH_MSG}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "git stash push に失敗しました。処理を中断します。"
        rm -f "${STASH_FILES_LIST_FILE}"
        exit 1
    fi
    STASHED=1
    log "stash push に成功しました: ${STASH_MSG}"
    # 自動コミットが受信内容とこのstashを取り違えないよう、
    # stashが触れるファイル一覧をこの時点で確定しておく。
    git stash show --include-untracked --name-only -z stash@{0} > "${STASH_FILES_LIST_FILE}" 2>>"${ERR_LOG_FILE}"
else
    log "未コミットの変更はありませんでした。"
fi

if ! git ls-remote --exit-code --heads origin "${REMOTE_BRANCH}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    log "リモートに ${REMOTE_BRANCH} が存在しないため、受信をスキップします"
    rm -f "${STASH_FILES_LIST_FILE}"
    if [ "${STASHED}" -eq 1 ]; then
        log "スキップのため、退避した stash を復元します。"
        if git stash pop >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
            log "stash pop に成功しました。"
        else
            err "git stash pop に失敗しました。git stash list で確認し、手動で復元してください。"
            echo "エラー: stash pop に失敗しました。git stash list で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
            exit 1
        fi
    fi
    echo "ℹ️ 受信するものはありません（${REMOTE_BRANCH} が存在しません）"
    exit 0
fi

log "git fetch origin ${REMOTE_BRANCH} を実行します。"
if ! git fetch origin "${REMOTE_BRANCH}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git fetch origin ${REMOTE_BRANCH} に失敗しました。"
    rm -f "${STASH_FILES_LIST_FILE}"
    if [ "${STASHED}" -eq 1 ]; then
        log "fetch 失敗のため、退避した stash を復元します。"
        if git stash pop >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
            log "stash pop に成功しました。"
        else
            err "git stash pop に失敗しました。git stash list で確認し、手動で復元してください。"
        fi
    fi
    exit 1
fi
log "git fetch に成功しました。"

WIP_COMMIT_HASH="$(git rev-parse "origin/${REMOTE_BRANCH}")"
WIP_COMMIT_SUBJECT="$(git log -1 --format=%s "origin/${REMOTE_BRANCH}")"

# cherry-pick予定の変更ファイル一覧を、cherry-pick実行"前"に確定しておく。
# こうすることで、後続の自動コミットで「wip-warp-scratchから受け取った
# ファイルだけ」を厳密にステージでき、このマシン側の他の変更を
# 誤って巻き込まない。
WIP_FILES_LIST_FILE="$(mktemp)"
git diff-tree --no-commit-id --name-only -r -z "origin/${REMOTE_BRANCH}" > "${WIP_FILES_LIST_FILE}"

log "git cherry-pick -n origin/${REMOTE_BRANCH} を実行します。"
if ! git cherry-pick -n "origin/${REMOTE_BRANCH}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git cherry-pick -n origin/${REMOTE_BRANCH} に失敗しました（コンフリクトの可能性があります）。git status で確認してください。"
    err "stash は保持したままにしています（自動での pop は行いません）。"
    echo "エラー: cherry-pick に失敗しました。git status で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
    rm -f "${WIP_FILES_LIST_FILE}" "${STASH_FILES_LIST_FILE}"
    exit 1
fi
log "cherry-pick に成功しました（未コミットの変更として適用）。"

if ! git reset >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git reset に失敗しました。"
    rm -f "${WIP_FILES_LIST_FILE}" "${STASH_FILES_LIST_FILE}"
    exit 1
fi
log "git reset でステージングを解除しました。"

# 受信ファイルと、このマシン側で退避したstashのファイルが重なっている場合、
# stash pop時に受信内容とローカル変更が同じファイル上でぶつかる可能性がある。
# そのケースをpushしてしまう前に検出し、自動コミットをスキップする。
# （grep -z はBSD/GNU/ugrepで意味が異なり移植性が無いため、NUL区切りの
#   一覧は事前に改行区切りへ変換してから -F -x で比較する）
OVERLAP=0
STASH_FILES_NL_FILE="$(mktemp)"
if [ "${STASHED}" -eq 1 ] && [ -s "${STASH_FILES_LIST_FILE}" ]; then
    tr '\0' '\n' < "${STASH_FILES_LIST_FILE}" | sed '/^$/d' > "${STASH_FILES_NL_FILE}"
    while IFS= read -r -d '' f; do
        if grep -Fxq "$f" "${STASH_FILES_NL_FILE}"; then
            OVERLAP=1
            log "受信ファイルとstash対象ファイルが重複しています: ${f}"
        fi
    done < "${WIP_FILES_LIST_FILE}"
fi
rm -f "${STASH_FILES_NL_FILE}"

PUSH_FAILED=0
if [ "${OVERLAP}" -eq 1 ]; then
    log "重複ファイルがあるため自動コミットをスキップします（stash popは通常通り試みます）。"
    echo "ℹ️ 受信内容とローカルの未コミット変更が同じファイルに触れるため、自動コミットをスキップしました。git status / git stash list で確認し、手動でコミットしてください。" >&2
elif [ -s "${WIP_FILES_LIST_FILE}" ]; then
    # --- ここから: 受け取った内容"だけ"を自動コミット・push ---
    log "受信内容の自動コミットを開始します。"
    if ! xargs -0 git add -- < "${WIP_FILES_LIST_FILE}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "受信ファイルの git add に失敗しました。git status で確認してください。stash は保持したままにしています。"
        echo "エラー: 受信ファイルの git add に失敗しました。git status で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
        rm -f "${WIP_FILES_LIST_FILE}" "${STASH_FILES_LIST_FILE}"
        exit 1
    fi

    PROJECT_NAME="$(basename "${REPO_ROOT}")"
    SYNC_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    COMMIT_MSG_FILE="$(mktemp)"
    {
        echo "chore(okaeri): auto-commit received WIP (${PROJECT_NAME}, ${SYNC_TIME})"
        echo ""
        echo "wip-warp-scratch: ${WIP_COMMIT_HASH:0:7} ${WIP_COMMIT_SUBJECT}"
        echo ""
        echo "Files:"
        tr '\0' '\n' < "${WIP_FILES_LIST_FILE}" | sed '/^$/d' | sed 's/^/  /'
    } > "${COMMIT_MSG_FILE}"

    if ! git commit -F "${COMMIT_MSG_FILE}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "受信内容のコミットに失敗しました。git status で確認してください。stash は保持したままにしています。"
        echo "エラー: 受信内容のコミットに失敗しました。git status で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
        rm -f "${WIP_FILES_LIST_FILE}" "${STASH_FILES_LIST_FILE}" "${COMMIT_MSG_FILE}"
        exit 1
    fi
    NEW_COMMIT_HASH="$(git rev-parse HEAD)"
    log "受信内容をコミットしました: ${NEW_COMMIT_HASH}"
    rm -f "${COMMIT_MSG_FILE}"

    log "git push origin HEAD を実行します。"
    if ! git push origin HEAD >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "git push に失敗しました。コミットはローカルに作成済みです（${NEW_COMMIT_HASH}）。手動で git push を実行してください（自動でのpull/mergeは行いません）。"
        echo "⚠️ 受信内容はコミットしましたが push に失敗しました。手動で git push を実行してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
        PUSH_FAILED=1
    else
        log "push に成功しました。"
    fi
    # --- 自動コミット・pushここまで ---
else
    log "受信対象ファイルがありませんでした（自動コミットはスキップ）。"
fi
rm -f "${WIP_FILES_LIST_FILE}" "${STASH_FILES_LIST_FILE}"

if [ "${STASHED}" -eq 1 ]; then
    log "退避しておいた元の変更を stash pop で復元します。"
    if ! git stash pop >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "git stash pop に失敗しました。git stash list で確認し、手動で復元してください。"
        echo "エラー: stash pop に失敗しました。git stash list で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
        exit 1
    fi
    log "stash pop に成功しました。"
fi

if [ "${PUSH_FAILED}" -eq 1 ]; then
    log "okaeri.sh は完了しましたが、push に失敗した項目があります。"
    exit 1
fi

if [ "${OVERLAP}" -eq 1 ]; then
    log "okaeri.sh が完了しました（自動コミットはスキップ、受信内容は未コミットのまま残しています）。"
    echo "エラー: 受信内容とローカルの未コミット変更が同じファイルに触れるため、自動コミットをスキップしました。git status で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
    exit 1
fi

log "okaeri.sh が正常に完了しました。"
echo "🏠 Context synchronized."

exit 0
