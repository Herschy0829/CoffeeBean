using UnityEngine;

namespace CoffeeBean.Telemetry.Demo
{
    /// <summary>
    /// 打点示例（场景挂载后运行）：
    /// 初始化后端（Editor mock）→ 上报事件 → 演示缓存（模拟 SDK 未就绪）。
    /// 真实 SDK（Umeng 等）实现 ITelemetryBackend 后经 CTelemetry.Initialize 热插拔。
    /// </summary>
    public sealed class TelemetryDemo : MonoBehaviour
    {
        private readonly CEditorTelemetryBackend _backend = new CEditorTelemetryBackend();

        private void Awake()
        {
            CTelemetry.Initialize(_backend);
        }

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 480, 240));
            GUILayout.Label("<b>Telemetry 演示</b>");

            GUILayout.BeginHorizontal();
            if (GUILayout.Button("打点 login", GUILayout.Width(140)))
            {
                CTelemetry.Track("login", ("uid", "player_1"), ("level", 3));
            }
            if (GUILayout.Button("打点 buy", GUILayout.Width(140)))
            {
                CTelemetry.Track("buy", ("item", "gold_100"), ("price", 6.0));
            }
            if (GUILayout.Button("打点 tutorial_step", GUILayout.Width(140)))
            {
                CTelemetry.Track("tutorial_step", ("step", 5));
            }
            GUILayout.EndHorizontal();

            GUILayout.Space(8);
            GUILayout.Label($"后端就绪: {CTelemetry.IsBackendReady}   待发送缓存: {CTelemetry.PendingCount}");
            GUILayout.Label($"后端收到事件: {_backend.ReceivedEvents.Count}");
            GUILayout.Label("（后端就绪的事件立即送出；未就绪进缓存，就绪后 FlushNow 发送）");
            GUILayout.EndArea();
        }
    }
}
