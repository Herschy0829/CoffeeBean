# CoffeeBean 广告与打点模块设计（com.coffeebean.ad / com.coffeebean.telemetry）

> 版本：v0.1（已实施）
> 状态：✅ 已实施（com.coffeebean.telemetry v0.1.0 + com.coffeebean.ad v0.1.0，2026-09-03 发布）

---

## 1. 背景与目标

调研 `IdleMedievalLife` 广告现状：`IAdService`（IsReady/ShowAd + Action 回调 + `AdServiceProvider` 静态注入 + `EditorAdService` 直接发奖）。痛点：

1. **无完整生命周期**：只有"播放"，缺初始化/预加载/卸载；无插屏/横幅区分
2. **无打点框架**：广告事件上报零散；业务打点（登录/支付）无统一入口
3. **无缓存**：打点/上报若 SDK 未就绪会丢事件

本设计：**两个关联模块**——打点框架（telemetry）+ 广告框架（ad），均可**热插拔后端**，由框架统一管理生命周期与回调，打点带缓存防丢失。

## 2. 模块一：com.coffeebean.telemetry（打点）

### 2.1 职责
- 统一事件上报入口（业务/登录/支付/广告共用），后端可热插拔（Umeng / ThinkingData / Firebase / 自建）
- **事件缓存**：SDK 未就绪时事件入内存队列（防丢），就绪后自动 flush；容量上限防爆
- Editor mock 后端（默认）：打日志，方便调试与测试

### 2.2 核心 API

```csharp
namespace CoffeeBean
{
    /// <summary>打点后端抽象（真实 SDK 各自实现，运行时热插拔）。</summary>
    public interface ITelemetryBackend
    {
        bool IsReady { get; }               // SDK 是否就绪（未就绪 → 框架缓存事件）
        void Initialize(string configJson); // 初始化（异步就绪后框架自动 flush）
        void TrackEvent(string eventName, IDictionary<string, object> properties);
        void Flush();                       // 主动刷新（可选）
    }

    /// <summary>打点门面（静态单例，框架统一管理）。</summary>
    public static class CTelemetry
    {
        // 后端（默认 Editor mock；真实 SDK 接入时替换）
        static ITelemetryBackend Backend;

        // 初始化（传入后端配置）
        static void Initialize(ITelemetryBackend backend, string configJson = null);

        // 上报事件（未就绪自动缓存，就绪自动 flush；返回是否实际送出）
        static bool Track(string eventName, IDictionary<string, object> properties = null);
        static bool Track(string eventName, params (string key, object value)[] props); // 便捷

        // 缓存状态（供统计/诊断）
        static int PendingCount { get; }    // 待发送缓存条数
        static void FlushNow();             // 手动强制 flush
        static void SetBackendReady(bool ready); // 后端就绪状态（测试/外部通知）
    }
}
```

### 2.3 缓存策略
- `Track` 时若 `Backend.IsReady` → 直接送；否则入内存队列（默认上限 1000，超出丢最旧并告警）
- 后端标记就绪（`SetBackendReady(true)` / Initialize 完成回调）→ 自动按序 flush 全部缓存
- 发送失败（后端异常）→ 事件丢弃（v0.1 不重试，防死循环；v0.2 可加持久化 + 重试）

### 2.4 Editor mock 后端（CEditorTelemetryBackend）
`IsReady = true`；`TrackEvent` 打 `CLog.Info`（可测试断言收到的事件）。

## 3. 模块二：com.coffeebean.ad（广告，依赖 telemetry）

### 3.1 职责
- 统一广告框架：初始化 → 预加载 → 就绪查询 → 播放 → 回调（rewarded/closed/failed）→ 卸载
- 后端可热插拔（AdMob / TopOn / Pangle / UnityAds 各自实现 `IAdProvider`）
- **v0.1 广告类型：激励视频 Rewarded + 插屏 Interstitial；插屏可配置不初始化**（`EnableInterstitial`）
- 广告事件（show/impression/click/close/reward/fail）自动经 `CTelemetry` 打点

### 3.2 核心 API

```csharp
namespace CoffeeBean
{
    /// <summary>广告类型。</summary>
    public enum CAdType { Rewarded, Interstitial }

    /// <summary>广告播放结果（回调参数）。</summary>
    public enum CAdResult { Completed, Skipped, Failed, Closed }

    /// <summary>广告回调。</summary>
    public sealed class CAdCallbacks
    {
        public Action OnRewarded;   // 激励达成（发奖点）
        public Action OnClosed;     // 广告关闭（含看完/跳过）
        public Action OnFailed;     // 加载/播放失败
    }

    /// <summary>广告后端抽象（真实 SDK 实现）。</summary>
    public interface IAdProvider
    {
        void Initialize(CAdConfig config, Action onReady);      // 初始化（ready 后框架可加载）
        bool IsRewardedReady(string placement);
        bool IsInterstitialReady(string placement);
        void LoadRewarded(string placement);                    // 预加载
        void LoadInterstitial(string placement);
        void ShowRewarded(string placement, CAdCallbacks cb);
        void ShowInterstitial(string placement, CAdCallbacks cb);
        void UnloadAll();                                       // 卸载（切账号/退出时）
    }

    /// <summary>广告配置（广告位 ID 等由消费工程给）。</summary>
    public sealed class CAdConfig
    {
        public bool EnableInterstitial;   // 是否初始化插屏（false = 不初始化，插屏 API 直接不可用）
        public string ConfigJson;         // 透传给 SDK 的配置
    }

    /// <summary>广告框架门面（统一管理 + 打点）。</summary>
    public static class CAdManager
    {
        // 初始化（热插拔：传入后端；Editor mock 默认自动成功）
        static void Initialize(IAdProvider provider, CAdConfig config = null);

        // 激励视频
        static bool IsRewardedReady(string placement = "default");
        static void LoadRewarded(string placement = "default");
        static void ShowRewarded(string placement = "default", CAdCallbacks cb = null);

        // 插屏（未初始化（EnableInterstitial=false）时 IsReady=false、Show 直接 Failed 回调）
        static bool IsInterstitialReady(string placement = "default");
        static void LoadInterstitial(string placement = "default");
        static void ShowInterstitial(string placement = "default", CAdCallbacks cb = null);

        static void UnloadAll();          // 卸载全部（后端 + 清状态）
        static CAdType LastShownType { get; }  // 诊断
    }
}
```

### 3.3 插屏可选初始化
`CAdConfig.EnableInterstitial = false`（默认 false）时：框架不调用 provider 的插屏初始化/加载；
`ShowInterstitial` 立即走 `OnFailed`（打点 `ad_interstitial_disabled`），业务可安全调用不崩。

### 3.4 打点联动（依赖 telemetry）
广告框架内置事件上报（全部经 `CTelemetry.Track`）：
- `ad_show`（type + placement）、`ad_impression`、`ad_click`（后端事件透传，v0.1 仅 show/close/reward/fail）
- `ad_reward`（发奖点，带 placement）、`ad_close`、`ad_fail`（带 reason）
> 模块依赖 `com.coffeebean.telemetry`（消费工程需同时安装；打点失败不影响广告主流程——Try/Catch 包裹）

### 3.5 Editor mock 后端（CEditorAdProvider）
- Initialize 直接回调 ready；`LoadRewarded/LoadInterstitial` 置 ready=true
- `ShowRewarded` 先打点再按顺序回调：OnRewarded → OnClosed（模拟看完发奖）
- `ShowInterstitial`：OnClosed（若 enable）；OnFailed（若 disable 或未 ready）
- 便于 Editor/真机调试与测试

## 4. 依赖与命名

| 模块 | 依赖 | 命名空间 | 说明 |
|------|------|----------|------|
| com.coffeebean.telemetry | tools | CoffeeBean | CTelemetry / ITelemetryBackend / CEditorTelemetryBackend |
| com.coffeebean.ad | tools + telemetry | CoffeeBean | CAdManager / IAdProvider / CAdConfig / CAdType / CAdCallbacks / CEditorAdProvider |

统一 `CoffeeBean` 根命名空间（`using CoffeeBean;` 即可）。C 前缀框架类型。Editor mock 放 Runtime（便于测试注入；真机 SDK 后端放独立包如 `com.coffeebean.ad.topon` 后续）。

## 5. 测试计划

**telemetry**（EditMode，mock/假后端）：
1. Track 就绪后端直送（后端收到事件）
2. Track 未就绪 → 入缓存（PendingCount+1，后端未收到）
3. SetBackendReady(true) → 自动 flush（后端按序收到全部缓存事件，PendingCount=0）
4. 缓存超上限丢最旧（防爆）
5. 便捷重载（params tuple）与字典等价
6. 后端异常不抛出（Track 返回 false，主流程安全）

**ad**（EditMode，Editor mock 后端注入）：
1. 初始化回调 ready（mock 立即）
2. ShowRewarded → 依次 OnRewarded + OnClosed（发奖点正确）
3. IsRewardedReady 加载后 true / 未加载 false
4. 插屏未启用（EnableInterstitial=false）：IsInterstitialReady=false、Show → OnFailed
5. 插屏启用：Show → OnClosed
6. Show 失败路径（mock 可配 fail）→ OnFailed + 打点
7. 广告事件已打到 telemetry（ad_show/ad_reward/ad_close/ad_fail 计数验证）
8. UnloadAll 清状态

## 6. 版本规划

- **v0.1.0**：telemetry（门面+缓存+Editor mock）+ ad（Rewarded/Interstitial 可选 + Editor mock + 打点联动）+ Sample + 测试
- **v0.2（候选）**：事件缓存持久化（进程退出前落盘）+ 重试；ad 后端拆分包（topon/admob）；横幅/开屏；收益回传（mediation）

## 7. 风险与取舍

- 广告 SDK 真机行为无法 EditMode 覆盖 → 抽象 `IAdProvider` 全 mock 测试；真实后端在消费工程验证
- 打点依赖 SDK 就绪异步 → 缓存队列（内存，v0.1）；进程退出前未 flush 的事件会丢（v0.2 持久化）
- 合规：广告/打点需用户同意（GDPR 等）→ 消费工程控制初始化时机，框架不内置同意弹窗
