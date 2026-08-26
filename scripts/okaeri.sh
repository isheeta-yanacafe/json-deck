#!/usr/bin/env bash
set -uo pipefail

# okaeri.sh
# 個人用のWIP同期スクリプト。別端末（Mac A）でodekake.shにより退避された
# WIPコードを、このMacの現在のブランチに未コミットの変更として取り込む。
# 現在のブランチやHEADには一切コミットを追加せず、履歴も変更しない。

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

if ! git diff --quiet || ! git diff --cached --quiet; then
    log "未コミットの変更（ステージ済み/未ステージ）を検出したため、stash に退避します。"
    STASH_MSG="okaeri.sh: auto stash $(date '+%Y-%m-%d %H:%M:%S')"
    if ! git stash push -u -m "${STASH_MSG}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "git stash push に失敗しました。処理を中断します。"
        exit 1
    fi
    STASHED=1
    log "stash push に成功しました: ${STASH_MSG}"
else
    log "未コミットの変更はありませんでした。"
fi

if ! git ls-remote --exit-code --heads origin "${REMOTE_BRANCH}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    log "リモートに ${REMOTE_BRANCH} が存在しないため、受信をスキップします"
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

log "git cherry-pick -n origin/${REMOTE_BRANCH} を実行します。"
if ! git cherry-pick -n "origin/${REMOTE_BRANCH}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git cherry-pick -n origin/${REMOTE_BRANCH} に失敗しました（コンフリクトの可能性があります）。git status で確認してください。"
    err "stash は保持したままにしています（自動での pop は行いません）。"
    echo "エラー: cherry-pick に失敗しました。git status で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
    exit 1
fi
log "cherry-pick に成功しました（未コミットの変更として適用）。"

if ! git reset >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git reset に失敗しました。"
    exit 1
fi
log "git reset でステージングを解除しました。"

if [ "${STASHED}" -eq 1 ]; then
    log "退避しておいた元の変更を stash pop で復元します。"
    if ! git stash pop >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
        err "git stash pop に失敗しました。git stash list で確認し、手動で復元してください。"
        echo "エラー: stash pop に失敗しました。git stash list で確認してください。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
        exit 1
    fi
    log "stash pop に成功しました。"
fi

log "okaeri.sh が正常に完了しました。"
echo "🏠 Context synchronized."

exit 0
