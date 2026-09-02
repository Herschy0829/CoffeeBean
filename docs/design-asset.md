# CoffeeBean 资源管理模块设计（com.coffeebean.asset）

> 版本：v0.1
> 状态：已实施（com.coffeebean.asset v0.1.0，2026-08-28 发布；后端 Addressables，可插拔 IAssetBackend）

---

## 1. 背景：Idle 项目资源管理现状与痛点

调研 `IdleMedievalLife` 的资源加载实现，存在**两套并存**的方案：

| 方案 | 载体 | 说明 |
|------|------|------|
| 旧：手写 AssetBundle | `Assets/AyFarme/AyScripts/B_Modules/AssetMgr` | `AssetMgr`(Singleton) + `IAssetLoader` 接口（`AssetEditorLoader` 编辑器直读 / `AssetBundleLoader` 真机）、`AssetBundleCache` 引用计数、依赖 manifest 递归加载、AB 加密（`EncryptHelp.GetKey`）、Excel 数据（GameDatas）AB/Resources 双路径 |
| 新：Addressables 2.9.1 | `Assets/AyFarme/AyScripts/AddressableSpts` | `AddressableResourceManager`(CSingletonMono，缓存+引用计数+handle 三字典)、`Ables` 静态组件扩展类（Image/Button/TMP_Text/Text/SpriteRenderer/AudioClip/字体/材质/Spine）、`CheckUpdateAndDownload`(catalog 更新+下载进度)、`SceneLoader`、`BuildLauncher`(已注释)；`AblesNaming` 定义地址前缀（`Ables_Fonts/Ables_Audio/...`），`TmpData` 定义动态字体参数 |

### 1.1 痛点

1. **双方案并存、接口不统一**：业务代码同时接触 `AssetMgr`（按 abName+assetName）与 `AddressableResourceManager`/`Ables`（按 address），无法平滑迁移
2. **缓存/引用计数混乱**：`Ables` 内 8 份静态字典（`_addSprite/_AddFontAsset/_AddMaterialAsset/_AddFont/_AddSkeletonDataAsset/_addAudioClips/_assetHandleDict`）**无引用计数**、常驻内存泄漏风险；`AddressableResourceManager` 有引用计数但两者互不共享
3. **TMP 动态字体逻辑重复**：`AddressableResourceManager.LoadFont` 与 `Ables.AddAblesRes` 各自实现一份 `TMP_FontAsset.CreateFontAsset`（参数同源于 `TmpData`）
4. **同步加载泛滥**：`Ables` 大量 `WaitForCompletion()` 阻塞主线程（UI 卡顿风险）
5. **更新流程不可复用**：`CheckUpdateAndDownload` 是场景内 MonoBehaviour（UI 文本+重试按钮写死），无法作为服务嵌入启动流程
6. **无统计/诊断**：无缓存命中率、内存水位、泄漏检测
7. **地址存在性检查重复**：`HasAddressableAsset` 每次都 `LoadResourceLocationsAsync`（同步 WaitForCompletion），性能隐患

## 2. 模块定位

**封装 Addressables 为统一资源加载门面**（替代旧 AssetBundle 手写方案与散落的组件扩展），提供：

- 统一 API：同步/异步加载、实例化、预加载、标签加载、引用计数释放
- 组件扩展：Image/Button/TMP_Text/Text/SpriteRenderer/AudioClip 一行绑定
- 更新下载服务：catalog 检测 → 下载（进度回调）→ 完成/失败/重试
- 统计诊断：缓存数/引用数/闲置清理/内存水位
- 场景加载封装

### 2.1 依赖与后端选型

- **后端固定为 Unity Addressables**（官方标准，Idle 新方案方向）；旧 AssetBundle 手写方案**不迁移**，仅在新模块中提供 `IAssetBackend` 抽象以便将来扩展
- 依赖声明：`com.unity.addressables` **声明依赖、来源消费方定**（同 save 模块声明 `com.cysharp.memorypack` 的做法）：package.json 声明版本提示，README 说明消费工程需自行安装（Package Manager 经 Unity Registry 解析，或本地副本），框架不强制来源
- 测试：dev 工程 manifest 增加 `com.unity.addressables`（2.9.1，Unity Registry 解析）+ 测试用 Addressable 资源（专用测试 group）

## 3. 设计

### 3.1 命名空间与类型

统一 `CoffeeBean` 根命名空间（对齐框架约定），C 前缀：

```
Runtime/
├── CAssetSystem.cs        资源门面（加载/实例化/预加载/释放/统计）
├── CAssetOptions.cs       配置（地址前缀规则、失败策略、字体参数）
├── CAssetExtensions.cs    组件绑定扩展（Image/TMP_Text/Text/Button/SpriteRenderer/AudioClip）
├── CCatalogUpdater.cs     更新下载服务（检测/下载/进度/重试）
├── CAssetSceneLoader.cs   场景加载封装
└── CAssetStats.cs         统计/诊断（可选，v0.1 合并进 CAssetSystem 简单版）
Tests/
└── ...                    核心逻辑测试（缓存/引用计数/释放语义）
Samples~/
└── AssetDemo/             IMGUI 演示：加载/实例化/预加载/释放/更新模拟
```

### 3.2 CAssetSystem（核心门面）

```csharp
public sealed class CAssetSystem
{
    // 初始化（Addressables.InitializeAsync 幂等）
    void Initialize();

    // 同步加载（Editor 下直读，真机 WaitForCompletion；缓存命中零开销）
    T LoadAsset<T>(string address) where T : Object;

    // 异步加载（地址存在性检查 + 加载 + 缓存 + 引用计数；C# Task，对齐 net 模块约定，不引入 UniTask）
    Task<T> LoadAssetAsync<T>(string address) where T : Object;

    // 批量/标签
    Task<List<T>> LoadAssetsByLabelAsync<T>(string label);
    Task PreloadAsync(IEnumerable<string> addresses);

    // 实例化
    GameObject Instantiate(string address, Transform parent = null);
    Task<GameObject> InstantiateAsync(string address, Transform parent = null);

    // 释放（引用计数）
    void Release(string address);          // 计数-1，归零释放
    void ForceRelease(string address);     // 忽略计数
    int ReleaseUnused();                   // 释放计数≤0 的闲置资源
    void ReleaseAll();

    // 查询/统计
    bool IsLoaded(string address);
    int GetRefCount(string address);
    bool TryGetCached<T>(string address, out T asset);
    CAssetStats GetStats();                // 缓存数/总引用数/各类型分布
}
```

> 异步统一用 `System.Threading.Tasks.Task`（`AsyncOperationHandle.Task` 直接转换），与 net 模块一致、无 UniTask 依赖；内部 `ConfigureAwait(false)` 按 net 模块约定处理（后台线程段）。

内部三字典对齐 `AddressableResourceManager` 经验：`_cache`(address→Object) + `_handles`(address→AsyncOperationHandle) + `_refCounts`(address→int)；**去重**：缓存命中时引用计数 +1 且不重复持有 handle；释放归零时 `Addressables.Release(handle)` 并清三字典。

**引用计数语义**（对齐 Idle 期望，防泄漏）：
- 每次 `LoadAsset/Async` 成功 → 计数 +1（含缓存命中）
- 每次 `Release` → 计数 -1；归零 → 真正释放
- 组件扩展（`Image.LoadSprite` 等）自动 +1，组件销毁自动 -1（`OnDestroy` 钩子，可选 v0.1 提供手动释放版本）
- 常驻资源（字体等）走 `Pin(address)`（计数永驻，`Unpin` 解除）

### 3.3 CAssetOptions

```csharp
public sealed class CAssetOptions
{
    bool AutoInitialize;               // 首次访问自动初始化（默认 true）
    bool FailSilently;                 // 加载失败仅告警不抛错（默认 true）
    string AddressPrefix;              // 可选统一前缀（默认 ""，对齐 AblesNaming 由业务决定）
    // TMP 动态字体参数（对齐 TmpData，避免逻辑重复）
    int FontSamplingPointSize = 68;
    int FontPadding = 12;
    GlyphRenderMode FontRenderMode = GlyphRenderMode.SDFAA;
    int FontAtlasWidth = 4096;
    int FontAtlasHeight = 4096;
    AtlasPopulationMode FontAtlasMode = AtlasPopulationMode.Dynamic;
    bool FontMultiAtlas = true;
}
```

### 3.4 CAssetExtensions（组件绑定，对齐 Ables 常用能力）

```csharp
// 统一走 CAssetSystem（共享缓存与引用计数），替代 Ables 8 份私有字典
image.LoadSprite(address);                      image.LoadSpriteAsync(address);
button.LoadSprite(address);                     button.LoadSpriteAsync(address);
spriteRenderer.LoadSprite(address);             spriteRenderer.LoadSpriteAsync(address);
tmpText.LoadFont(address);                      tmpText.LoadFontAsync(address);   // 动态字体（参数来自 CAssetOptions）
text.LoadFont(address);                         text.LoadFontAsync(address);
audioSource.LoadClip(address);                  audioSource.LoadClipAsync(address);
GameObject.InstantiateFromAddress(address, parent);   // 静态便捷
```

### 3.5 CCatalogUpdater（更新下载服务，替代场景内 MonoBehaviour）

```csharp
public sealed class CCatalogUpdater
{
    // 一次性检查更新：检测 → 下载（每帧回调进度）→ 完成/失败（可重试）
    Task<bool> UpdateAsync(
        IProgress<float> progress = null,       // 0~1 下载进度
        CancellationToken token = default);
    // 内置失败重试（可选次数/间隔）
    int MaxRetry = 3;
}
```

启动流程：`var ok = await updater.UpdateAsync(progress); if (ok) EnterGame();`

### 3.6 场景加载

```csharp
Task<Scene> LoadSceneAsync(string address, LoadSceneMode mode = Single, bool activateOnLoad = true);
```

### 3.7 与旧方案的取舍（v0.1 明确不做）

- **不迁移旧 AssetBundle 方案**：`AssetMgr/AssetBundleLoader` 保持 Idle 工程内私有，新项目直接用本模块
- **不做 AB 加密**：Addressables 官方无内置加密；如需可后续做自定义 `AssetBundleProvider`（v0.2 候选）
- **不做资源引用打包分析**（依赖树/冗余检测）：Editor 深度工具，v0.2 候选

## 4. 测试计划

dev 工程引入 `com.unity.addressables`（2.9.1）+ 测试 Addressable group（`CoffeeBeanTestAssets`：测试 Sprite/Prefab/TextAsset 若干）。

EditMode 测试（核心逻辑，Addressables 初始化为本地 catalog）：
1. **缓存语义**：加载→计数 1；重复加载→计数 2（不重复持有 handle）；Release×2 → 真正释放（IsLoaded false）
2. **缓存命中**：第二次 LoadAsset 不触发新的 Addressables 加载（用计数验证）
3. **释放归零**：Release 到 0 后 IsLoaded=false、GetRefCount=0、TryGetCached=false
4. **ForceRelease**：忽略计数直接释放
5. **ReleaseUnused**：计数≤0 的闲置资源被清理
6. **标签加载**：LoadAssetsByLabelAsync 返回组内全部资源
7. **预加载**：PreloadAsync 后全部 IsLoaded
8. **组件扩展**：Image.LoadSprite 后 sprite 赋值正确、计数 +1
9. **统计**：GetStats 缓存数/引用总数正确
10. **失败容错**：不存在地址 → null 返回 + 告警（FailSilently）

## 5. 版本规划

- **v0.1.0**：CAssetSystem + CAssetOptions + CAssetExtensions（加载/释放/统计核心）+ CCatalogUpdater + AssetDemo + 测试
- **v0.2.x（已实施）**：Pin/Unpin 常驻资源（0.2.0）、组件自动释放钩子 CAutoRelease（0.2.1）、资源依赖分析工具（0.2.2）

## 6. 依赖与风险

- **依赖**：`com.unity.addressables`（版本消费工程定，建议 2.9+）；测试/Sample 用 dev 工程内建的测试 group
- **风险**：Addressables EditMode 测试需初始化 catalog（本地模式，无网络）；同步加载在真机仍会阻塞（文档明示推荐异步）
- **AB 加密取舍（v0.2 不实施，明示）**：Addressables 资源加密需自定义 AssetBundleProvider / `IDataConverter` 构建期转换 +
  运行时解密加载管线，涉及构建管线集成且测试难覆盖，对中小项目收益有限（混淆级保护，key 仍在客户端）。
  已落地的替代：配置 JSON（excel 模块）走字节级 XOR 加密；如需 AB 加密，建议项目按
  [官方自定义 Provider 方案](https://docs.unity3d.com/Packages/com.unity.addressables@2.9/api/UnityEngine.ResourceManagement.ResourceProviders.IDataConverter.html) 在项目层扩展，模块不内置。
- **测试环境**：dev 工程 manifest 增加 `com.unity.addressables`（registry 解析），新增测试资源目录（`Assets/AssetTest/` + AddressableAssetSettings 配置）
