#!/usr/bin/env bash
set -uo pipefail

# odekake.sh
# 個人用のWIP同期スクリプト。開発中のコードを一時的にリモートブランチへ
# 退避し、別端末で引き継げるようにする。ローカルの履歴は汚さない。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${REPO_ROOT}/scripts/logs"
LOG_FILE="${LOG_DIR}/sync.log"
ERR_LOG_FILE="${LOG_DIR}/sync.error.log"
LOCK_FILE="${LOG_DIR}/.warp.lock"
REMOTE_BRANCH="wip-warp-scratch"

mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${ERR_LOG_FILE}"
}

cleanup() {
    rm -f "${LOCK_FILE}"
}

if [ -e "${LOCK_FILE}" ]; then
    err "既に実行中です（lockファイル: ${LOCK_FILE}）。多重起動を中止します。"
    exit 1
fi

touch "${LOCK_FILE}"
trap cleanup EXIT

cd "${REPO_ROOT}" || { err "リポジトリルートへの移動に失敗しました: ${REPO_ROOT}"; exit 1; }

log "odekake.sh を開始します。"

# https://github.com への疎通確認（5秒間隔で最大6回リトライ、計30秒）
CONNECTED=0
for i in 1 2 3 4 5 6; do
    if curl -sSf --max-time 5 -o /dev/null "https://github.com"; then
        CONNECTED=1
        break
    fi
    log "疎通確認リトライ ${i}/6 に失敗しました。5秒後に再試行します。"
    sleep 5
done

if [ "${CONNECTED}" -ne 1 ]; then
    err "https://github.com への疎通確認に失敗しました（30秒間リトライ後）。中止します。"
    exit 1
fi

log "https://github.com への疎通確認に成功しました。"

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>>"${ERR_LOG_FILE}")"
if [ -z "${ORIGINAL_BRANCH}" ]; then
    err "現在のブランチ名の取得に失敗しました。"
    exit 1
fi

if ! git add -A 2>>"${ERR_LOG_FILE}"; then
    err "git add -A に失敗しました。"
    exit 1
fi

# 秘密情報が含まれていそうなファイル名パターンの安全チェック
# （開発者が誤って設定ファイル等をコミットしてしまうケアレスミスを防ぐためのローカルチェック）
SECRET_NAME_PATTERN='^\.env|\.env$|\.pem$|\.key$|_secret|^secret_|credentials|\.p12$|id_rsa|id_ed25519'

FLAGGED_FILES=""
while IFS= read -r f; do
    [ -z "${f}" ] && continue
    base="$(basename "${f}")"
    if echo "${base}" | grep -Eq "${SECRET_NAME_PATTERN}"; then
        FLAGGED_FILES="${FLAGGED_FILES}${f}"$'\n'
    fi
done <<< "$(git diff --cached --name-only)"

if [ -n "${FLAGGED_FILES}" ]; then
    git reset >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"
    err "秘密情報を含む可能性のあるファイル名が検出されたため、ステージを取り消して中断しました:"
    while IFS= read -r flagged; do
        [ -z "${flagged}" ] && continue
        err "  - ${flagged}"
    done <<< "${FLAGGED_FILES}"
    echo "エラー: 秘密情報を含む可能性のあるファイル名が検出されました。処理を中断します。詳細は ${ERR_LOG_FILE} を確認してください。" >&2
    exit 1
fi

if git diff --cached --quiet; then
    log "変更なし"
    echo "変更なし"
    exit 0
fi

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
COMMIT_MSG="WIP-WARP: ${TIMESTAMP} (from ${ORIGINAL_BRANCH})"

if ! git commit -m "${COMMIT_MSG}" >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git commit に失敗しました。"
    exit 1
fi

log "コミットしました: ${COMMIT_MSG}"

if ! git push origin HEAD:"${REMOTE_BRANCH}" --force >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git push origin HEAD:${REMOTE_BRANCH} --force に失敗しました。"
    exit 1
fi

log "リモートブランチ ${REMOTE_BRANCH} へのpushに成功しました。"

if ! git reset --soft HEAD~1 >>"${LOG_FILE}" 2>>"${ERR_LOG_FILE}"; then
    err "git reset --soft HEAD~1 に失敗しました。ローカルのコミットが残っている可能性があります。"
    exit 1
fi

log "ローカルコミットを取り消し、未コミット状態に戻しました。"
log "odekake.sh が正常に完了しました。"

echo "🚀 Warp complete. (${ORIGINAL_BRANCH} → ${REMOTE_BRANCH})"

exit 0
