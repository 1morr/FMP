# 文档更新提醒

## ⚠️ 重要提醒

**在完成重大代码修改后，必须同时更新：**
1. **CLAUDE.md** - 项目核心文档（供 AI 快速了解项目）
2. **Serena 记忆文件** - 详细架构/实现文档

如果不及时更新，会导致：
- 新对话无法获取正确的项目信息
- AI 可能使用过时的架构/API 进行建议
- 重复犯已经解决过的错误

---

## 何时需要更新文档

### CLAUDE.md 更新场景

| 修改类型 | 需要更新的章节 |
|----------|---------------|
| 音频架构变更 | "Three-Layer Audio System"、"File Structure" |
| 核心设计决策变更 | "Key Design Decisions" |
| 新增核心命令/工具 | "Common Commands" |
| 状态管理变更 | "State Management: Riverpod" |
| 数据层变更 | "Data Layer" |

### Serena 记忆更新场景

| 修改类型 | 需要更新的记忆 | 示例 |
|----------|---------------|------|
| **依赖包变更** | `project_overview` | 更换 `just_audio_background` → `audio_service` |
| **音频系统架构** | `audio_system` | 添加新的播放模式、修改状态管理 |
| **新增/删除服务类** | `architecture` | 添加 `FmpAudioHandler`，删除 `PlaylistDownloadTask` |
| **下载系统变更** | `download_system` | 修改路径计算、缓存策略 |
| **UI 页面结构** | `ui_pages_details` | 新增页面、修改导航 |
| **设计决策/经验教训** | `refactoring_lessons` | 新的最佳实践、踩坑经历 |
| **代码风格规范** | `code_style` | 新的命名约定、格式要求 |

---

## 如何更新文档

### CLAUDE.md 更新
```
mcp__plugin_serena_serena__replace_content(
  relative_path: "CLAUDE.md",
  needle: "旧内容",
  repl: "新内容",
  mode: "literal"  // 或 "regex"
)
```

### Serena 记忆更新

**1. 小范围修改（推荐）**
```
mcp__plugin_serena_serena__edit_memory(
  memory_file_name: "xxx",
  needle: "旧内容",
  repl: "新内容",
  mode: "literal"  // 或 "regex"
)
```

**2. 大范围重写**
```
mcp__plugin_serena_serena__write_memory(
  memory_file_name: "xxx",
  content: "完整新内容..."
)
```

**3. 删除过时记忆**
```
mcp__plugin_serena_serena__delete_memory(memory_file_name: "xxx")
```

---

## 检查清单

完成重大修改后，问自己：

- [ ] 是否添加/删除了依赖包？→ 更新 **CLAUDE.md** + `project_overview`
- [ ] 是否添加/删除了服务类？→ 更新 **CLAUDE.md** "File Structure" + `architecture`
- [ ] 是否修改了核心架构？→ 更新 **CLAUDE.md** 相关章节 + 相关记忆
- [ ] 是否有新的设计决策？→ 更新 **CLAUDE.md** "Key Design Decisions" + `refactoring_lessons`
- [ ] 是否有踩坑经验需要记录？→ 更新 `refactoring_lessons`

**如果任何一项为"是"，请立即更新 CLAUDE.md 和相关记忆！**
