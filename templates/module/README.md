# com.coffeebean.template

TODO: 一句话描述这个模块。

- **独立可用**：不装 CoffeeBean Core 也能单独安装使用
- **装了 Core 自动接入**：Bridge 程序集提供模块标记与生命周期，被 Core 发现、启停与版本校验
- **示例**：`Samples~/TemplateDemo`（Package Manager → 本模块 → Samples → Import）

## 安装

```json
{
  "dependencies": {
    "com.coffeebean.template": "https://github.com/<你的账号>/com.coffeebean.template.git#v0.1.0"
  }
}
```

> 可选：同时安装 `com.coffeebean.core`（并在入口场景挂 `CoffeeBeanBootstrap`），本模块即纳入框架引导。

## 用法

```csharp
using CoffeeBean;   // 所有模块主类型统一在 CoffeeBean 根命名空间

// TODO: 换成你的模块真实 API
```

## 依赖

- **无必需依赖**：模块本身零 Core 依赖，可独立工作
- 可选：`com.coffeebean.core` —— 安装后由 Bridge 自动接入（服务注册 / 生命周期 / Hub 管理）
- 其他 CoffeeBean 模块依赖：TODO（若有，写进 `package.json` 的 `dependencies`，**不要**写 `com.coffeebean.core`）

## 结构（Bridge 模式）

```
Runtime/                              主程序集：不引用 Core
  CoffeeBean.Template.asmdef            versionDefines: 存在 core → COFFEEBEAN_CORE
  TemplateService.cs                    模块代码（占位，请替换）
  Bridge/                              Core 可选集成
    Bridge.cs                             模块标记 + ICoffeeBeanModule（#if COFFEEBEAN_CORE）
    CoffeeBean.Template.Bridge.asmdef     defineConstraints: COFFEEBEAN_CORE
Editor/                               编辑器程序集（不引用 Core）
Tests/                                EditMode 测试
Samples~/TemplateDemo/                示例（必选）
link.xml                              保留主程序集 + Bridge 程序集
```

详见 `PLACEHOLDERS.md`。
