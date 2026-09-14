# 模块模板使用说明

复制本目录到 `packages/` 下并重命名，然后全局替换占位符。

> 本模板采用 **Bridge 模式**：模块**不硬依赖 Core**，装了 Core 才自动接入框架。
> 这是当前框架的标准做法（`tools` / `pooling` / `asset` / `ui` / `save` 等 14 个模块都如此），
> 请勿退回"主程序集直接引用 CoffeeBean.Core"的旧写法。

## 1. 命名替换

| 占位符 | 替换为 | 位置 |
|--------|--------|------|
| `com.coffeebean.template` | 你的模块 id，如 `com.coffeebean.events` | 目录名、`package.json`、`Runtime/Bridge/Bridge.cs` |
| `CoffeeBean.Template` | 程序集名，如 `CoffeeBean.Events` | **4 个 asmdef** 的文件名与 `name`、`rootNamespace`、`references`、`link.xml` |
| `Template` | 显示名称，如 `Events` | `Runtime/Bridge/Bridge.cs` 的 `DisplayName` 与 `TemplateModule` 类名 |
| `TemplateService` | 你的模块主类型名，如 `EventBus` | `Runtime/TemplateService.cs`（**不要删成空目录**：主程序集需要至少一个源文件才会产出程序集，而 Bridge / Editor / Tests / Demo 的 asmdef 都引用它） |

## 2. 版本

- `package.json` 的 `version` 与 `Runtime/Bridge/Bridge.cs` 里 `CoffeeBeanModule` 的 `Version` **必须一致**
  （不一致会让 Core 的兼容性校验、Hub 显示的模块版本全是错的 —— 框架里已经踩过这个坑）
- 发布时打 git tag：`v0.1.0`，并在 `CHANGELOG.md` 记录

## 3. 依赖（Bridge 模式的关键差异）

Core 的依赖声明分**两处**，语义不同，别写反：

| 位置 | 写什么 | 为什么 |
|------|--------|--------|
| `package.json` → `dependencies` | **只列非 Core 的**直接依赖（如 `com.coffeebean.tools`）；**不要写 `com.coffeebean.core`** | 保持模块可脱离 Core 独立安装/编译 |
| `Runtime/Bridge/Bridge.cs` → `Dependencies` | 列**全部**直接依赖的 CoffeeBean 模块，**包含 `com.coffeebean.core`** | Core 的拓扑排序读的就是这个数组；Bridge 只在装了 Core 时才编译，故写 core 不会产生"缺依赖"告警 |

- 主 Runtime asmdef 的 `references` **不要**写 `CoffeeBean.Core`（保持零 Core 依赖）
- 只在 `Runtime/Bridge/CoffeeBean.Template.Bridge.asmdef` 里引用 `CoffeeBean.Core`
- 声明第三方包（Addressables / MemoryPack 等）时，`package.json` 声明版本提示，README 说明来源由消费工程决定

## 4. 目录约定

| 目录 | 内容 |
|------|------|
| `Runtime/` | 运行时程序集（必选）。`CoffeeBean.Template.asmdef` 带 `versionDefines`（存在 core → 定义 `COFFEEBEAN_CORE`）；至少保留一个源文件（如 `TemplateService.cs`） |
| `Runtime/Bridge/` | **Core 可选集成（必选）**：`Bridge.cs`（模块标记 + `ICoffeeBeanModule` 生命周期，整体包在 `#if COFFEEBEAN_CORE` 内）+ 带 `defineConstraints: ["COFFEEBEAN_CORE"]`、`autoReferenced: false` 的 asmdef |
| `Editor/` | 编辑器程序集（可选）。`includePlatforms: ["Editor"]`，**不引用 Core**；`CoffeeBeanToolAttribute.cs` 是给 Hub 反射识别用的同名副本（需要 Hub 工具入口时保留）。若某个编辑器工具**确实**要用 Core 的编辑器 API，再单独加一个带 `defineConstraints` 的 Editor Bridge 程序集 |
| `Tests/` | EditMode 测试（可选）。asmdef 用官方格式 `optionalUnityReferences: ["TestAssemblies"]`；包在工程 `Packages` 目录外时，还需在**消费工程的 manifest** 的 `testables` 里列出本包（见根仓库 `dev/Packages/manifest.json` 示例） |
| `Samples~/` | **示例（必选）**：改造成你的模块真实演示；`package.json` 的 `samples` 字段同步 |
| `link.xml` | 保留**主程序集 + Bridge 程序集**，确保模块标记在 IL2CPP 裁剪后仍可被发现 |

## 5. 接入框架

1. 推送到你的 GitHub 仓库并打 tag
2. 在 `com.coffeebean.core/Editor/Resources/coffeebean.registry.json` 登记模块（id / repo / latest tag）
3. 消费工程打开 `Window > CoffeeBean` 即可一键安装

## 6. 发布检查清单

- [ ] `package.json` 的 `version` 与 Bridge 的 `Version` 一致
- [ ] 打了 tag 且推送（`vX.Y.Z`）
- [ ] `CHANGELOG.md` 有对应条目
- [ ] 在 GitHub 建 Release（正文取自 CHANGELOG 当版本条目）
- [ ] `Samples~/` 随功能更新
- [ ] 在**消费工程 manifest 的 `testables`** 里登记本包，本地跑通 EditMode 测试
