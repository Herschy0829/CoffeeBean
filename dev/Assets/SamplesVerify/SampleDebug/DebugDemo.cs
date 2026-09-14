using UnityEngine;

namespace CoffeeBean.Debug.Demo
{
    /// <summary>
    /// 调试模块示例（场景挂载后运行）：
    /// 注册几个示例作弊命令，按键开关控制台。
    /// 控制台操作：回车执行命令、↑/↓ 历史、类型过滤、搜索、清空、拷贝。
    /// </summary>
    public sealed class DebugDemo : MonoBehaviour
    {
        private int _gold;

        private void Awake()
        {
            // 注册示例作弊命令（业务实际用法）
            CDebug.Register("add_gold", "加金币（add_gold 数量）", args =>
            {
                _gold += int.Parse(args[0]);
                CLog.Info("DebugDemo", $"金币 +{args[0]}，当前 {_gold}");
            }, 1);

            CDebug.Register("set_gold", "设置金币（set_gold 数量）", args =>
            {
                _gold = int.Parse(args[0]);
                CLog.Info("DebugDemo", $"金币设置为 {_gold}");
            }, 1);

            CDebug.Register("print_help", "打印示例文本", _ => CLog.Info("DebugDemo", "调试模块示例：控制台 + 作弊命令"));
        }

        private void Update()
        {
            // F12 开关控制台（可自定义按键）
            if (Input.GetKeyDown(KeyCode.F12))
            {
        #if COFFEEBEAN_DEV_TOOLS
        CDebug.ToggleConsole();
#endif
            }
        }

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 360, 120));
            GUILayout.Label("<b>Debug 演示</b>");
            GUILayout.Label($"金币: {_gold}");
            GUILayout.Label("按 F12 开关控制台；控制台输入 add_gold 100 / set_gold 999 / help");
            GUILayout.EndArea();
        }
    }
}
