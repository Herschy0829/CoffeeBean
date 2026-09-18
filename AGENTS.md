# CoffeeBean — 工作区指令

模块化 Unity 框架：**一个模块 = 一个 GitHub 仓库 = 一个独立功能**。游戏工程用 UPM Git 引用接入，Core 模块统一管理安装/卸载/升级/依赖。设计入口 `docs/design.md`（**先读 §0**：部分原始原则已被实际架构取代）。

## 铁律

1. `packages/` 下每个模块是**独立 git 仓库**，被根仓库 `.gitignore` 忽略 → 改模块要在 `packages/<模块>` 内各自提交推送，**不要**在根仓库提交模块内容。
2. `dev/`（联调 Unity 工程）**入库**：模块只是 UPM 包跑不了测试，CI 需要消费工程。只排除生成物。
3. Core 是**可选**的：模块主程序集零 Core 依赖，只在 `Runtime/Bridge/` 用 `versionDefines` + `defineConstraints: ["COFFEEBEAN_CORE"]` 条件编译接入；不装 Core 模块照常独立工作。
4. `CoffeeBeanToolAttribute` 在各模块 Editor 程序集里是**同名副本**（Hub 按全名反射匹配）→ 改它必须同步所有副本。
5. Hub 工具形态**纯结构判定**：`EditorWindow` 派生类 → 独立窗口；`static class` + `public static void DrawTool(Action requestRepaint)` → 内嵌面板。**不要给 attribute 加字段**。
6. 新模块从 `templates/module/` 复制（见其 `PLACEHOLDERS.md`）。模块版本**只有一处真相**：`packages/com.coffeebean.core/Editor/Resources/coffeebean.registry.json`（CI 从它读各模块 latest tag，别在 README / 工作流里硬编码）。
7. 测试：`powershell -File scripts/run-editmode-tests.ps1`（CI 实际用 game-ci action，不调这个脚本）。

## 记忆系统

本仓库用「常驻索引 + 按需明细」的自维护记忆，**不依赖任何插件**：

- 常驻指令 = `AGENTS.md`（本文件，入库）+ `AGENTS.local.md`（**本机私有，不入库**，放环境速查与私有约束）。
- 明细记忆库 = `.dsh/memory/`（**本机私有，不入库**）。若该目录不存在，说明这份 checkout 未启用记忆系统，按普通仓库处理即可。
- **接活前**：任务涉及本项目架构/约定时，先读 `.dsh/memory/INDEX.md`，命中再读对应 `facts/*.md`；不要为此全仓 grep 或重读 `docs/`。
- **收尾时**：只把**会复用的结论**写进 `facts/`（一条一文件）；能从代码 / `git log` / `docs/` 直接得出、或 `docs/` 已有的**不写**。跨会话推进状态写 `state/current.md`（唯一一份，原地更新）。
- **压缩**：满足任一条件就跑 `powershell -File scripts/memory.ps1` 并按其报告压缩——① 常驻指令（本文件 + `AGENTS.local.md`）合计 >5 KB；② `INDEX.md` >60 行；③ 单条 fact >60 行；④ 新增 ≥10 条 fact；⑤ 用户说「整理/压缩记忆」。动作与报告格式见 `.dsh/memory/README.md`。
