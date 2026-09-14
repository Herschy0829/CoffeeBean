using UnityEngine;

namespace CoffeeBean.UI.Demo
{
    /// <summary>
    /// UI 模块示例入口（场景挂载后运行，IMGUI 演示）：
    /// 打开/关闭面板、层级、栈式导航、传参。
    /// 说明：Sample 无预制体资源，演示面板用代码动态构造（真实项目用 CBind + 代码生成）。
    /// </summary>
    public sealed class UIDemo : MonoBehaviour
    {
        private string _status = "就绪";

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 480, 300));

            GUILayout.Label("<b>CoffeeBean UI 演示</b>");
            GUILayout.Label(_status);

            GUILayout.Space(8);
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("打开面板 (Common)", GUILayout.Width(150), GUILayout.Height(30)))
            {
                OpenDemo("Common 面板");
            }
            if (GUILayout.Button("打开面板 (PopUI)", GUILayout.Width(150), GUILayout.Height(30)))
            {
                OpenDemo("PopUI 弹窗");
            }
            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            if (GUILayout.Button("关闭面板", GUILayout.Width(150), GUILayout.Height(30)))
            {
                CUIManager.Instance.ClosePanel<UIDemoPanel>();
                _status = "已关闭面板";
            }
            if (GUILayout.Button("返回 (Back)", GUILayout.Width(150), GUILayout.Height(30)))
            {
                CUIManager.Instance.Back("UIDemoPanel");
                _status = "Back 返回上一个";
            }
            GUILayout.EndHorizontal();

            GUILayout.Space(8);
            GUILayout.Label("说明：Single 类型同面板复用；层级决定挂载节点；");
            GUILayout.Label("Stack.Push 记录并关闭当前，Pop/Back 重开上一个。");
            GUILayout.Label("代码生成：预制体挂 CBind → Inspector『生成面板代码』→ 编译后自动绑定字段。");

            GUILayout.EndArea();
        }

        private void OpenDemo(string title)
        {
            var panel = CUIManager.Instance.OpenPanel<UIDemoPanel>(
                uiData: new UIDemoPanelData(title));
            _status = panel != null ? $"已打开: {title}（层级 {panel.Info.Level}）" : "打开失败";
        }
    }
}
