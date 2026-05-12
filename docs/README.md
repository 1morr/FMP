# FMP 文档地图

此目录保存面向开发者和维护者阅读的项目文档。AI coding agent 的强约束规则在仓库根目录 [AGENTS.md](../AGENTS.md)。

## 当前文档

| 文档 | 读者 | 用途 |
|------|------|------|
| [开发文档](development.md) | 贡献者 | 项目概览、架构地图、当前开发规则摘要 |
| [构建指南](build-guide.md) | 本地构建者 | Android 和 Windows 本地构建说明 |
| [构建与发布指南](build-and-release.md) | 维护者 | CI 发布流程、签名、GitHub Releases、更新资产 |
| [VM Service 调试指南](debugging-with-vm-service.md) | 调试者 / agent | 通过 Dart VM Service 和 Marionette 做运行时检查 |
| [历史重构流水](history/refactoring-log.md) | 维护者 | 归档记录，仅作背景参考，不作为当前实现规范 |

## 权威来源

- `AGENTS.md` 是 AI coding agent 的权威规则：架构边界、迁移规则、UI 编码约束，以及会影响代码修改的项目坑点。
- `docs/development.md` 是人类贡献者的 onboarding 文档，只摘要当前架构并链接到 `AGENTS.md`，不要重复维护每条 agent 规则。
- `.serena/memories/` 应保持窄而补充。如果某个 memory 变成当前核心规则，应合并到 `AGENTS.md` 或独立文档，并删除重复 memory。
- 历史记录可以放在 `docs/history/`，但必须标记为归档，不能当作当前实现规范使用。

## 维护规则

- 架构、数据模型、迁移、UI 或音源行为变化：优先更新 `AGENTS.md`。
- 本地构建环境或打包前置条件变化：更新 `build-guide.md`。
- CI 产物命名、发布 workflow、签名 secrets、应用内更新资产识别变化：更新 `build-and-release.md`。
- 运行时调试流程、VM Service 脚本或 Marionette 用法变化：更新 `debugging-with-vm-service.md`。
- 不要把同一条规则复制到多个文件，除非目标文档确实拥有对应读者和维护责任。
