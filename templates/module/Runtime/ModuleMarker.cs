// CoffeeBean 模块标识：每个模块的 Runtime 程序集必须声明。
// 复制模板后请替换（三处保持一致）：
//   com.coffeebean.template -> 你的模块 id（与 package.json 的 name 一致）
//   0.1.0                   -> 与 package.json 的 version 一致
//   DisplayName/Description -> 模块显示名称与描述
// 注意：Id/Version 是构造参数（位置参数），DisplayName 等是可选命名参数。
using CoffeeBean;

[assembly: CoffeeBeanModule(
    "com.coffeebean.template",
    "0.1.0",
    DisplayName = "Template",
    Description = "TODO: 描述这个模块的功能。",
    Dependencies = new[] { "com.coffeebean.core" }   // 只声明直接依赖
)]
