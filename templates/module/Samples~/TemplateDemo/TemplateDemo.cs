using UnityEngine;

namespace CoffeeBean.Template.Samples
{
    /// <summary>
    /// 模块示例（每个模块必带 Samples~）：演示本模块的核心用法。
    /// 复制模板后请把本文件改造成你的模块的真实示例。
    /// 替换点：
    ///   - 类名 TemplateDemo → &lt;你的模块&gt;Demo
    ///   - 命名空间 CoffeeBean.Template.Samples → CoffeeBean.&lt;你的模块&gt;.Samples
    ///   - 下方 DoSomething() 换成模块真实功能的调用演示
    /// </summary>
    public sealed class TemplateDemo : MonoBehaviour
    {
        private string _status = "Ready.";

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 420, 200));
            GUILayout.Label("<b>CoffeeBean Template Demo</b>", GUILayout.Height(22));
            GUILayout.Label("状态: " + _status);
            if (GUILayout.Button("调用模块功能", GUILayout.Height(32))) DoSomething();
            GUILayout.EndArea();
        }

        private void DoSomething()
        {
            // TODO: 换成你的模块真实功能的调用演示
            _status = "示例调用完成（请替换为真实功能）";
            Debug.Log("[TemplateDemo] 示例调用");
        }
    }
}
