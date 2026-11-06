# GitHub Releases 发布

## 自动构建

`.github/workflows/build-release.yml` 在以下情况执行：

- 推送到 main、提交 Pull Request：在 Apple Silicon / Intel 原生 runner 上运行回归并生成安装包。
- 手动运行 Actions：执行相同构建，不创建公开 Release。
- 推送 `vX.Y.Z` 标签：两种架构都通过测试、打包和校验后，创建公开 GitHub Release，上传六个附件。

普通分支工作流仅使用仓库读取权限。仅发布 job 使用内置 `GITHUB_TOKEN` 的 `contents: write` 权限，无需配置个人 token 或付费 Apple 开发者凭据。
官方 Actions 固定到已核对的提交。GitHub 提供的 macos-15 / macos-15-intel 分别用于 arm64 / x86_64，任务启动时再次检查实际架构。

## 发布步骤

1. 修改根目录 `VERSION`（格式 `X.Y.Z`）。
2. 添加 `docs/releases/X.Y.Z.md`，写明用户可感知的更新和安装提示。
3. 提交并推送到 main，确认 Build and Release 工作流成功。
4. 创建并推送匹配的版本标签：

```bash
git tag -a v1.0.0 -m "EyeTimer 1.0.0"
git push origin v1.0.0
```

标签版本与 VERSION 不一致会终止任务。Release 只有在两种架构的任务全部成功后才发布；包上传失败时不会把缺少附件的 Release 当作成功。
已发布的同名版本不自动覆盖；修复后发布新的版本号。若 GitHub CLI 上传中断后留下草稿，在 Releases 中检查并处理草稿后重试。

## 本地打包

```bash
bash Tools/package_release.sh
```

默认构建当前机器架构。可以通过 `APP_ARCH=arm64` 或 `APP_ARCH=x86_64` 指定目标；交叉编译不代表该架构已经实机验证。
已经完成 `bash Tools/run_checks.sh` 时可使用 `bash Tools/package_release.sh --skip-build`。跳过构建时仍会校验版本、架构、应用签名和许可证，防止误包旧产物。

输出在 `dist/releases/`：

| 文件 | 用途 |
| --- | --- |
| `EyeTimer-X.Y.Z-arm64.dmg` | M 系列 Mac 拖拽安装 |
| `EyeTimer-X.Y.Z-x86_64.dmg` | Intel Mac 拖拽安装 |
| 同名 `.zip` | 备用下载，保留应用目录和可执行权限 |
| 每种架构各一份 `.sha256` | 对应 DMG 与 ZIP 的 SHA-256 校验和 |

DMG 包含 EyeTimer.app、指向 Applications 的快捷方式、安装说明与 MIT 许可证。应用资源目录也包含许可证。
打包过程检查应用签名、磁盘镜像完整性、ZIP 完整性与校验和。产物位于 dist，不提交到 Git 历史；下载通过 Releases 提供。

## 签名与公证

当前使用临时签名，未使用 Developer ID 证书或 Apple 公证。构建与校验通过不代表 Gatekeeper 会信任下载包，首次打开可能需要用户按 [安装帮助](install.md) 操作。
未来拥有开发者会员后，可以增加 Developer ID 签名、公证与 stapling，再相应修改安装说明。不要通过禁用系统安全机制来改变发布包的状态。

## 文档与许可

README 面向使用者，开发和测试信息放在 [development.md](development.md)。项目使用 MIT 许可证，发布包必须包含 LICENSE。
