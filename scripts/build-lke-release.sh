#!/usr/bin/env bash
# LingkeAI 定制引擎（zeroclaw fork lke/main）构建脚本——固化 2026-11-11/12
# 实测全流程。构建参数逐字对齐官方发布工作流（docs/lke/CUSTOMIZING.md）。
# 日志实时双写终端与 target/lke-logs/（排查以日志文件为准）。
#
# 用法：scripts/build-lke-release.sh [options]
#   --tag vX.Y.Z-lke.N   构建成功后打定制 tag（已存在则校验指向当前 HEAD）
#   --target <triple>    目标 triple（缺省宿主 aarch64-apple-darwin）
#   --rust <version>     rust 工具链（缺省 1.98.0，官方 CI 同款）
#   --desktop-repo <p>   构建并打 tag 后联动桌面仓打包内嵌种子（需 --tag）
#   --skip-tests         跳过 LKE 定制点定向测试（不建议）
#   --skip-seed          跳过桌面种子联动（等价不给 --desktop-repo）
#
# 验证机制（任何一项失败即中止）：
#   A. cargo fmt --all --check（格式门禁）
#   B. LKE-CUSTOM 源码标记存在性（LKE-001/002/003 定制点在位）
#   C. 定向测试回归（runtime/tools/channels 三批，覆盖全部定制点）
#   D. 产物：三件二进制存在 + --version 冒烟输出含定制 tag
#   E. [--tag] tag 指向校验；[--desktop-repo] 种子打包产物齐全
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=""; TARGET="$(rustc -vV 2>/dev/null | awk '/^host:/{print $2}')"; RUST="1.98.0"
DESKTOP_REPO=""; SKIP_TESTS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --rust) RUST="$2"; shift 2 ;;
    --desktop-repo) DESKTOP_REPO="$2"; shift 2 ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --skip-seed) DESKTOP_REPO=""; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

LOG_DIR="target/lke-logs"; mkdir -p "${LOG_DIR}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${LOG_DIR}/build-lke-${TAG:-working}-${STAMP}.log"
exec > >(tee "${LOG}") 2>&1
echo "=== LKE engine build  target=${TARGET} rust=${RUST} tag=${TAG:-none} ==="

step() { printf '\n■ %s\n' "$1"; }
RC=0

# ── 1. 工具链 ─────────────────────────────────────────────────────────────
step "1/7 工具链检查（rust ${RUST}）"
if ! rustup run "${RUST}" rustc --version >/dev/null 2>&1; then
  echo "  ✗ VERIFY FAIL: rustup toolchain ${RUST} 未安装"; echo "    rustup toolchain install ${RUST}"; exit 1
fi
rustup run "${RUST}" rustc --version
[[ "${TARGET}" == aarch64-apple-darwin || "${TARGET}" == x86_64-apple-darwin ]] || {
  echo "  ✗ VERIFY FAIL: 本脚本覆盖 mac 打包目标（got ${TARGET}）"; exit 1; }
rustup target list --installed --toolchain "${RUST}" | grep -q "${TARGET}" || {
  echo "  ✗ VERIFY FAIL: ${RUST} 缺 ${TARGET} std——rustup target add ${TARGET} --toolchain ${RUST}"; exit 1; }
echo "  ✓ toolchain + target std 就绪"

# ── 2. 验证 A：格式门禁 ───────────────────────────────────────────────────
step "2/7 验证 A：cargo fmt --all --check"
if ! cargo +"${RUST}" fmt --all -- --check; then
  echo "  ✗ VERIFY FAIL: 格式不符合 rustfmt（cargo fmt -p <crate> 修复后重跑）"; exit 1
fi
echo "  ✓ 格式全仓合规"

# ── 3. 验证 B：LKE-CUSTOM 标记存在性 ──────────────────────────────────────
step "3/7 验证 B：定制点源码标记（docs/lke/REGISTRY.md）"
check_marker() { # file marker min
  local n; n=$(grep -c "$2" "$1" 2>/dev/null || true)
  if [[ "$n" -lt "$3" ]]; then echo "  ✗ VERIFY FAIL: $1 缺 $2（got $n, want ≥$3）"; exit 1; fi
  echo "  ✓ $1: $2 ×$n"
}
check_marker crates/zeroclaw-runtime/src/agent/turn/delivery_defaults.rs 'LKE-CUSTOM(LKE-001)' 1
check_marker crates/zeroclaw-tools/src/ask_user.rs            'LKE-CUSTOM(LKE-001)' 1
check_marker crates/zeroclaw-tools/src/escalate.rs            'LKE-CUSTOM(LKE-001)' 1
check_marker crates/zeroclaw-api/src/channel.rs               'LKE-CUSTOM(LKE-002)' 1
check_marker crates/zeroclaw-channels/src/lark.rs             'LKE-CUSTOM(LKE-002)' 1
check_marker crates/zeroclaw-channels/src/orchestrator/mod.rs 'LKE-CUSTOM(LKE-002)' 1
check_marker crates/zeroclaw-tools/src/ask_user.rs            'LKE-CUSTOM(LKE-003)' 1
check_marker crates/zeroclaw-tools/src/escalate.rs            'LKE-CUSTOM(LKE-003)' 1

# ── 4. 验证 C：定向测试回归 ───────────────────────────────────────────────
if [[ "${SKIP_TESTS}" -eq 1 ]]; then
  step "4/7 跳过定向测试（--skip-tests，不建议）"
else
  step "4/7 验证 C：LKE 定制点定向测试"
  cargo +"${RUST}" test -q -p zeroclaw-runtime --lib -- delivery_defaults; [[ $? -eq 0 ]] || exit 1
  cargo +"${RUST}" test -q -p zeroclaw-tools --lib -- ask_user escalate; [[ $? -eq 0 ]] || exit 1
  cargo +"${RUST}" test -q -p zeroclaw-channels --lib --features channel-lark -- lark_ channel_turn_context sender_profile; [[ $? -eq 0 ]] || exit 1
  echo "  ✓ 三批定向测试全绿（runtime/tools/channels）"
fi

# ── 5. 官方参数构建三件套 ─────────────────────────────────────────────────
step "5/7 官方参数构建（xtask dist selection + --locked）"
FEATURES="$(cargo +"${RUST}" run --quiet -p xtask --bin generate -- features --selection dist --target "${TARGET}")"
echo "  FEATURES=${FEATURES}"
cargo +"${RUST}" build --release --locked --no-default-features --features "${FEATURES}" --target "${TARGET}"
cargo +"${RUST}" build --release --locked -p zerocode  --target "${TARGET}"
cargo +"${RUST}" build --release --locked -p zerorelay --target "${TARGET}"

# ── 6. 验证 D：产物存在 + 冒烟 ────────────────────────────────────────────
step "6/7 验证 D：产物与版本冒烟"
REL="target/${TARGET}/release"
for b in zeroclaw zerocode zerorelay; do
  [[ -x "${REL}/$b" ]] || { echo "  ✗ VERIFY FAIL: ${REL}/$b 不存在或不可执行"; exit 1; }
done
echo "  ✓ 三件二进制在位"
VER_OUT="$("${REL}/zeroclaw" --version)"; RC=$?
if [[ ${RC} -ne 0 || -z "${VER_OUT}" ]]; then
  echo "  ✗ VERIFY FAIL: --version 冒烟失败（exit ${RC}；syspolicyd 挂死时重启机器，见 runbook）"; exit 1
fi
echo "  ✓ 冒烟：${VER_OUT}"
if [[ -n "${TAG}" ]]; then
  [[ "${VER_OUT}" == *"${TAG}"* ]] || echo "  ⚠ 版本输出不含 ${TAG}（git describe 与 tag 不符？工作树 dirty 或 tag 未打）"
fi

# ── 7. tag + 桌面种子联动 ─────────────────────────────────────────────────
if [[ -n "${TAG}" ]]; then
  step "7/7 打 tag ${TAG}"
  if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    HEAD_SHA="$(git rev-parse HEAD)"; TAG_SHA="$(git rev-parse "refs/tags/${TAG}^{commit}")"
    [[ "${HEAD_SHA}" == "${TAG_SHA}" ]] || { echo "  ✗ VERIFY FAIL: tag 已存在但指向 ${TAG_SHA} ≠ HEAD ${HEAD_SHA}"; exit 1; }
    echo "  ✓ tag 已存在且指向当前 HEAD"
  else
    git tag -a "${TAG}" -m "LingkeAI custom build (${TARGET}) — LKE customs per docs/lke/REGISTRY.md"
    echo "  ✓ tag 已打"
  fi
  if [[ -n "${DESKTOP_REPO}" ]]; then
    step "联动桌面仓打包内嵌种子"
    ABS_REPO="$(pwd)"
    ( cd "${DESKTOP_REPO}" && npm run seed:zeroclaw -- --local "${ABS_REPO}" --tag "${TAG}" )
    SEED_TAG_FILE="${DESKTOP_REPO}/build/zeroclaw-seed/seed-tag"
    [[ -f "${SEED_TAG_FILE}" && "$(cat "${SEED_TAG_FILE}")" == "${TAG}" ]] || {
      echo "  ✗ VERIFY FAIL: 桌面种子 seed-tag ≠ ${TAG}"; exit 1; }
    echo "  ✓ 桌面种子已就位（${SEED_TAG_FILE}）"
  fi
else
  step "7/7 跳过 tag 与种子联动（未给 --tag / --desktop-repo）"
fi

echo
echo "✅ LKE 引擎构建完成：${REL}/{zeroclaw,zerocode,zerorelay}（日志：${LOG}）"
[[ -n "${TAG}" ]] && echo "   下一步发布：桌面仓 node scripts/build-release.mjs --version <X.Y.Z> --upload"
