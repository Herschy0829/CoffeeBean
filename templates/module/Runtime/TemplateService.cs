namespace CoffeeBean
{
    /// <summary>
    /// 模块运行时代码的入口占位（**请替换为你的模块真实类型**）。
    ///
    /// 约定：
    /// · 主类型统一放在 `CoffeeBean` 根命名空间 —— 业务只需 `using CoffeeBean;` 即可用到所有模块主类型；
    ///   模块内部的辅助类型 / 编辑器工具 / 示例保留 `CoffeeBean.X` 子命名空间（父命名空间自动可见）。
    /// · 框架自有类型用 `C` 前缀（如 `CPool`、`CSaveSystem`），接口用 `I` 前缀。
    /// · 需要被其他模块使用时，不要暴露具体类型，而是在 Bridge 的 OnLoad 里注册进
    ///   `context.Services`，让调用方按接口获取（避免模块间程序集横向依赖）。
    ///
    /// 注意：本文件不要删空 —— 主 Runtime 程序集需要至少一个源文件才会产出程序集，
    /// 而 `Runtime/Bridge`、`Editor`、`Tests`、`Samples~` 的 asmdef 都引用它。
    /// </summary>
    public sealed class TemplateService
    {
        /// <summary>TODO: 换成你的模块 API。</summary>
        public string DoSomething() => "template";
    }
}
