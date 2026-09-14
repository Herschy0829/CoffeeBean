using UnityEngine;

namespace CoffeeBean.AD.Demo
{
    /// <summary>
    /// 广告示例（场景挂载后运行）：Editor mock 后端（自动成功），演示激励视频/插屏。
    /// 真实 SDK 接入：实现 IAdProvider（或后续拆分包）→ CAdManager.Initialize(yourProvider, config)。
    /// </summary>
    public sealed class AdDemo : MonoBehaviour
    {
        private readonly CEditorAdProvider _mock = new CEditorAdProvider();
        private string _status = "未初始化";
        private int _rewards;

        private void Awake()
        {
            CAdManager.Initialize(_mock, new CAdConfig { EnableInterstitial = true });
            _status = "已初始化（插屏启用）";
        }

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 520, 260));
            GUILayout.Label("<b>AD 演示（Editor mock）</b>");
            GUILayout.Label($"状态: {_status}");

            GUILayout.Space(8);
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("预加载激励", GUILayout.Width(130)))
            {
                CAdManager.LoadRewarded("ad_r_levelup");
                _status = $"激励已加载，ready={CAdManager.IsRewardedReady("ad_r_levelup")}";
            }
            if (GUILayout.Button("播放激励", GUILayout.Width(130)))
            {
                CAdManager.ShowRewarded("ad_r_levelup", new CAdCallbacks
                {
                    OnRewarded = () => { _rewards++; _status = $"已发奖（第 {_rewards} 次）"; },
                    OnClosed = () => Debug.Log("[AdDemo] 激励关闭"),
                    OnFailed = () => _status = "激励播放失败",
                });
            }
            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            if (GUILayout.Button("预加载插屏", GUILayout.Width(130)))
            {
                CAdManager.LoadInterstitial("ad_i_levelup");
                _status = $"插屏已加载，ready={CAdManager.IsInterstitialReady("ad_i_levelup")}";
            }
            if (GUILayout.Button("播放插屏", GUILayout.Width(130)))
            {
                CAdManager.ShowInterstitial("ad_i_levelup", new CAdCallbacks
                {
                    OnClosed = () => Debug.Log("[AdDemo] 插屏关闭"),
                    OnFailed = () => _status = "插屏播放失败（未启用或未就绪）",
                });
            }
            GUILayout.EndHorizontal();

            GUILayout.Space(8);
            GUILayout.Label("广告事件（show/reward/close/fail）已自动打到 Telemetry（控制台可见日志）。");
            GUILayout.Label("真实 SDK：实现 IAdProvider 热插拔，业务代码不变。");
            GUILayout.EndArea();
        }
    }
}
