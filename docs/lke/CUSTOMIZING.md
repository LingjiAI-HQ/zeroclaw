# LingkeAI 定制开发规范（zeroclaw fork）

本仓库是 LingkeAI 对 [zeroclaw-labs/zeroclaw](https://github.com/zeroclaw-labs/zeroclaw)
的二次开发 fork，只做**小幅度的内部调整与支持**。构建参数完全参考官方生成的
二进制包（见[构建与打包](#构建与打包)），定制不影响官方 feature 选择与产物形态。
2026-11-11 拍板：推翻此前"只使用官方原版二进制、不二次改造"的原则，改为本仓
定制构建；定制内容全部登记在 [REGISTRY.md](REGISTRY.md)。

## 分支与版本模型

- `master`：纯上游镜像，只允许 fast-forward 到 `upstream/master`，**禁止直接提交**。
- `lke/main`：定制集成分支。所有定制提交落在这里；上游更新按
  [上游同步流程](#上游同步流程) 合入。禁止 rebase 已推送历史。
- 定制 tag：`v<上游 Cargo 版本>-lke.<序号>`（如 `v0.9.0-lke.1`），打在
  `lke/main` 上，随桌面端发版走。桌面端 `compareTags` 已支持该后缀的
  版本比较：先比上游三段版本，再比 `-lke.<序号>`（无后缀视为 0），
  保证 only-upgrade 语义对定制版同样成立。

## 定制三律（抗上游冲突）

1. **登记先行**：动代码前先在 [REGISTRY.md](REGISTRY.md) 登记
   （ID、动机、文件清单、上游对应 issue/PR、冲突风险），提交信息引用该 ID。
2. **增量优先**：新增文件、新增字段、新增函数优先于修改上游行；结构体
   构造点依赖 `..Default::default()` 兜底，保证新增字段不破坏既有构造点。
   不重排无关代码，不做无关格式化，不改 `Cargo.toml` 的依赖与 feature
   定义（确需修改的，必须在 REGISTRY 说明并评估升级冲突面）。
3. **标记就位**：每个定制点加一行 `// LKE-CUSTOM(LKE-xxx): <一句话动机>`
   注释。上游合并冲突 triage 时 `grep -rn "LKE-CUSTOM"` 即可拿到全部
   定制点清单，与 REGISTRY 逐项对照。

## 上游同步流程

```bash
git fetch upstream
git checkout master && git merge --ff-only upstream/master && git push origin master
git checkout lke/main && git merge upstream/master --no-ff \
  -m "merge upstream/master (<shortlog>) — LKE customs triage per docs/lke/CUSTOMIZING.md"
```

冲突处理规范（按序执行）：

1. `git diff --name-only --diff-filter=U` 列冲突文件，对照
   `grep -rn "LKE-CUSTOM"` 与 REGISTRY.md 逐项确认每个定制的存活状态。
2. 上游已采纳我们的修复（对应 PR 合并）→ 删除本地定制，在 REGISTRY 标记
   **上游化** 并记录上游 commit，后续版本起不再携带该 hunk。
3. 冲突解决方向 = **上游新行为 + 定制意图在新基线上重新表达**。禁止整块
   吞下本地旧版本掩盖上游变更。
4. 语义不明的冲突（上游重构导致定制意图无处安放）→ 停止合并，上缴拍板，
   不猜测落点。
5. 合并后门禁：定向 `cargo test`（覆盖 REGISTRY 全部定制点）+ 按官方参数
   完整构建 + 桌面端联调冒烟，全绿后推送并按需发新 `-lke.N` tag。

## 构建与打包

构建参数**逐字对齐官方发布工作流**
（`.github/actions/build-release-payloads/action.yml`）：

```bash
TARGET=aarch64-apple-darwin   # 打包机按宿主 triple
FEATURES="$(cargo +1.98.0 run --quiet -p xtask --bin generate -- \
  features --selection dist --target "$TARGET")"
cargo +1.98.0 build --release --locked --no-default-features \
  --features "$FEATURES" --target "$TARGET"
cargo +1.98.0 build --release --locked -p zerocode  --target "$TARGET"
cargo +1.98.0 build --release --locked -p zerorelay --target "$TARGET"
```

- **工具链**：`1.98.0`，与官方发布 CI 的 pin 一致。
- **feature 集**：由 xtask 规范注册表按 target 解析（`--selection dist`），
  即官方标准发行版携带的全部渠道与能力（lark/telegram/discord/email/git/
  matrix/webhook/filesystem/acp-server/whatsapp-web 等）。**引擎侧保持
  官方渠道全集开放，不在构建层裁剪渠道；桌面端启用哪些渠道由桌面业务
  在渠道配置面逐步开启。**
- **`--no-default-features`**：generator 输出已包含该 target 的默认叶子，
  官方注释明确 union 回默认集会造成隐式 feature 漂移，必须照抄。
- 产物：`target/$TARGET/release/{zeroclaw,zerocode,zerorelay}`，
  布局与官方 `scripts/ci/package_release_archive.sh` 一致（根部二进制，
  `web/dist/` 可选——桌面端不消费 dashboard，未构建 web 时可缺省）。

打包进桌面端：在桌面仓执行
`npm run seed:zeroclaw -- --local <本仓路径> --tag v0.9.0-lke.<N>`，
脚本会把上述产物打包为 `build/zeroclaw-seed/`（tar.gz + SHA256SUMS +
seed-tag），由 electron-builder 烘焙进安装包，运行时经 provisioner
校验/解压/冒烟后原子换装。

## 许可与商标

上游以 MIT/Apache-2.0 双许可发布，fork 合规。定制二进制只随 LingkeAI
桌面安装包内部分发，不以 ZeroClaw 名义独立对外发布发行包，规避商标问题。
