# &lt;你的模块&gt; Demo

模块示例：每个模块必须提供 Sample（Package Manager 可一键导入）。
导入：Package Manager → 本模块 → Samples → Import。

复制模板后请更新：
1. 目录名 `TemplateDemo` → `<你的模块>Demo`
2. asmdef 名字与引用（`CoffeeBean.Template.Demo` → `CoffeeBean.<模块>.Demo`）
3. `TemplateDemo.cs`：替换为模块真实功能的演示
4. `package.json` 的 `samples` 字段同步
