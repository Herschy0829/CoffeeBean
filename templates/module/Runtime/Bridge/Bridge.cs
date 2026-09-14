#if COFFEEBEAN_CORE
// ============================================================================
// CoffeeBean 模块标识 + Core 生命周期集成（Bridge 模式）
//
// 为什么单独放一个程序集：
//   · 主 Runtime 程序集（CoffeeBean.Template）**不引用 Core**，因此本模块不装 Core
//     也能独立编译、独立使用。
//   · 主 asmdef 用 versionDefines 声明：只要工程里存在 com.coffeebean.core，
//     就为本程序集定义 COFFEEBEAN_CORE。
//   · 本 Bridge asmdef 带 defineConstraints: ["COFFEEBEAN_CORE"]，因此**只有在装了 Core 时
//     才参与编译**，进而才把模块标记暴露给 Core 的程序集扫描。
//
// 复制模板后请替换（两处保持一致）：
//   com.coffeebean.template -> 你的模块 id（与 package.json 的 name 一致）
//   0.1.0                   -> 与 package.json 的 version 一致
//   DisplayName/Description -> 模块显示名称与描述
// 注意：Id/Version 是构造参数（位置参数），DisplayName 等是可选命名参数。
// ============================================================================
using CoffeeBean;

[assembly: CoffeeBeanModule(
    "com.coffeebean.template",
    "0.1.0",
    DisplayName = "Template",
    Description = "TODO: 描述这个模块的功能。",
    // 只声明直接依赖的 CoffeeBean 模块。Core 必须列在这里：
    // Core 的拓扑排序读的就是这个数组（Bridge 只在装了 Core 时才编译，所以这里写 core 不会导致"缺依赖"告警）。
    Dependencies = new[] { "com.coffeebean.core" }
)]

namespace CoffeeBean
{
    /// <summary>
    /// Core 集成：在 <see cref="OnLoad"/> 里把模块的服务注册进服务注册表，
    /// 其他模块即可通过 <c>context.Services.Get&lt;T&gt;()</c> 使用，而无需引用本模块程序集。
    /// </summary>
    public sealed class TemplateModule : ICoffeeBeanModule
    {
        public void OnLoad(CoffeeBeanContext context)
        {
            // TODO: 在这里注册你的服务，例如：
            // context.Services.Register<IMyService>(new MyService());
            context.Log("CoffeeBean.Template integrated.");
        }

        public void OnStart()
        {
        }

        public void OnShutdown()
        {
        }
    }
}
#endif
