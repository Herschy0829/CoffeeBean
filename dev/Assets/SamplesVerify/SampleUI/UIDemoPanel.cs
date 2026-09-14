using UnityEngine;
using UnityEngine.UI;

namespace CoffeeBean.UI.Demo
{
    /// <summary>演示面板数据（打开传参）。</summary>
    public class UIDemoPanelData : CUIPanelData
    {
        public string Title;

        public UIDemoPanelData(string title) => Title = title;
    }

    /// <summary>
    /// 演示面板：展示生命周期与传参。
    /// 真实项目中用 CBind 标记节点 + Inspector"生成面板代码"自动生成字段绑定。
    /// </summary>
    public class UIDemoPanel : CUIPanel
    {
        [SerializeField] private Text _titleText;

        private UIDemoPanelData _data;

        protected override void OnInit(ICUIData uiData = null)
        {
            _data = uiData as UIDemoPanelData ?? new UIDemoPanelData("默认标题");
        }

        protected override void OnOpen(ICUIData uiData = null)
        {
            _data = uiData as UIDemoPanelData ?? _data;
        }

        protected override void OnShow()
        {
            if (_titleText != null) _titleText.text = $"面板: {_data.Title}";
            Debug.Log($"[UIDemo] 打开面板 {_data.Title}");
        }

        protected override void OnClose()
        {
            Debug.Log($"[UIDemo] 关闭面板 {_data.Title}");
        }
    }
}
