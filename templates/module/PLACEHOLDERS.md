# 模块模板使用说明

复制本目录到 `packages/` 下并重命名，然后全局替换以下占位符：

## 1. 命名替换

| 占位符 | 替换为 | 位置 |
|--------|--------|------|
| `com.coffeebean.template` | 你的模块 id，如 `com.coffeebean.events` | 目录名、`package.json`、`ModuleMarker.cs` |
| `CoffeeBean.Template` | 程序集名，如 `CoffeeBean.Events` | asmdef 文件名（3 个）与文件内 `name`、`rootNamespace`、`references`、`link.xml` |
| `Template` | 显示名称，如 `Events` | `ModuleMarker.cs` 的 `DisplayName` |

## 2. 版本

- `package.json` 的 `version` 与 `ModuleMarker.cs` 的 `Version` 必须一致
- 发布时打 git tag：`v0.1.0`，并在 `CHANGELOG.md` 记录

## 3. 依赖

- `package.json` 的 `dependencies` 与 `ModuleMarker.cs` 的 `Dependencies` 必须一致（只声明直接依赖）
- 默认依赖 `com.coffeebean.core`；需要更多模块时逐个添加

## 4. 目录约定

| 目录 | 内容 |
|------|------|
| `Runtime/` | 运行时程序集（必选），含 `ModuleMarker.cs` |
| `Editor/` | 编辑器程序集（可选），不需要可删除并同步 `package.json` 无影响 |
| `Tests/` | EditMode 测试（可选）。测试 asmdef 用官方格式 `optionalUnityReferences: ["TestAssemblies"]`；包在项目 `Packages` 目录外时，还需在**消费工程的 manifest** 的 `testables` 里列出本包（见根仓库 `dev/Packages/manifest.json` 示例） |
| `Samples~/` | **示例（必选）**：见 `Samples~/TemplateDemo/` 骨架，改造成你的模块真实演示；`package.json` 的 `samples` 字段同步 |

## 5. 接入框架

1. 推送到你的 GitHub 仓库并打 tag
2. 在 `com.coffeebean.core/Editor/Resources/coffeebean.registry.json` 登记模块（id / repo / latest tag）
3. 消费工程打开 `Window > CoffeeBean > Module Manager` 即可一键安装
