# CoffeeBean 原生导出定制模块设计（Android Studio / Xcode 工程导出）

> 版本：v0.1（已实施）
> 状态：✅ 已实施（com.coffeebean.build v0.1.0，2026-09-03 发布；本设计实现期间经开源调研校准，见 §14）

---

## 1. 背景与目标

Unity 游戏接 SDK / 渠道 / 原生能力时，导出 **Android Studio（Gradle）工程** 与 **iOS Xcode 工程** 后，几乎总要往工程里"写东西"：

- **Android**：AndroidManifest 权限/组件、gradle 依赖与签名、gradle 属性、`libs` 下的 aar/jar、res/strings、proguard 规则；构建机上的 SDK/NDK/JDK 环境
- **iOS**：Info.plist 权限文案与键值、系统/三方 framework、静态库与链接参数、Build Settings、Capability/entitlements、新文件进 target

Unity 自带能力（`Assets/Plugins/Android` 模板、`Assets/Plugins/iOS` 自动入工程）覆盖"静态、写死"的诉求；但**动态、按项目/按构建配置/按渠道注入**的需求（同一套代码导出不同包、SDK 按需插拔、CI 出包）需要导出后处理。

本模块：**统一的"原生工程导出定制"框架** —— 一条导出后处理管线 + Android/iOS 两套平台注入器 + 声明式配置（JSON/ScriptableObject）与代码注册两种用法；注入逻辑纯 C#（XML/文本），EditMode 可测；薄适配层接 Unity 构建回调与平台 API。

### 1.1 设计原则（沿用 CoffeeBean 惯例）
1. 模块独立 UPM 仓库；`C` 前缀框架类型；主类型在 `CoffeeBean` 根命名空间
2. **注入引擎 = 纯逻辑（可测）**，Unity 编辑器 API 只出现在薄适配层 —— EditMode 测试不打真实构建即可验证全部注入内容
3. 幂等：同一工程反复导出/重复执行不产生重复节点、重复行、重复库
4. 配置三通道：默认内置 → JSON/ScriptableObject 资产 → 代码注册（覆盖/追加）
5. 步骤可扩展：SDK 集成方写一个 `IExportStep` 即插即用（与 Core Hub 的 CoffeeBeanToolAttribute 解耦思路一致）
6. Sample 必带；每次版本更新同步 Sample 与测试

---

## 2. 范围与非目标

### v0.1.0 范围（本期）
- 导出后处理管线：Android（Gradle 工程 / export project 模式）+ iOS（Xcode 工程）
- Android 注入器：Manifest（权限/组件/meta-data/application 属性/tools 处理）、gradle 文本锚点注入（依赖/仓库/signing/flavor）、gradle.properties、libs 追加 aar/jar、strings/proguard 追加、**构建环境校验（SDK/NDK/JDK 路径，CI 环境变量检查）**
- iOS 注入器：Info.plist 键值（权限文案/URL Scheme/ATT/SKAdNetwork/ATS/自定义键）、系统 framework + 三方 framework/.a 追加与 embed、Other Linker Flags（-ObjC 等）、Build Settings 键值注入、基础 Capability（Push/BackgroundModes/Sign in with Apple）、entitlements 生成、新文件（.m/.swift/.h/.bundle）加入 target
- 幂等检测、失败即中止构建并报清晰错误、导出日志归档
- Sample：`Samples~/NativeExportDemo`；EditMode 测试（fake 工程验证注入产物）
- 文档：README/CHANGELOG/LICENSE；Core 可选 Bridge（注册模块标记）

### 非目标（后续候选 v0.2+）
- 真实构建/出包（调 gradle/xcodebuild）——只做工程定制
- 完整多渠道（flavor 矩阵 UI）——先给文本注入原语
- CocoaPods `pod install` 自动执行 —— v0.2 候选（先写 Podfile）
- 云端签名/证书管理 —— 只做工程侧 signing 注入
- 图标/启动图生成

---

## 3. 模块命名与结构（建议，待确认）

建议单包 `com.coffeebean.build`（displayName：CoffeeBean Build：原生工程导出定制），
备选：`com.coffeebean.export` / `com.coffeebean.native`。**一个包**的理由：两平台共享管线/配置/日志/幂等模型；拆两包会重复这些骨架。平台专属代码放独立 Editor asmdef，避免相互污染。

```
com.coffeebean.build/
├── package.json / README.md / CHANGELOG.md / LICENSE.md / link.xml
├── Runtime/                      # 纯逻辑（零 Unity 平台依赖，可 EditMode 测）
│   ├── CoffeeBean.Build.asmdef
│   ├── AssemblyInfo.cs           # InternalsVisibleTo(测试)
│   ├── Core/
│   │   ├── CExportConfig.cs      # 配置模型（可 JSON 序列化）
│   │   ├── CExportSession.cs     # 一次导出的会话：路径/目标平台/日志/幂等表
│   │   ├── CExportRunner.cs      # 按序执行步骤（Android 步骤 → iOS 步骤）
│   │   ├── IExportStep.cs        # 步骤接口
│   │   └── CExportLog.cs         # 分平台日志 + 汇总（失败抛 CExportException）
│   ├── Android/
│   │   ├── CAndroidManifest.cs   # XmlDocument 包装：权限/组件/meta-data 注入（幂等）
│   │   ├── CGradleFile.cs        # 文本锚点注入器（dependencies{ } 内插行等）
│   │   ├── CGradleProperties.cs  # key=value 读写（幂等）
│   │   ├── CAndroidLibs.cs       # libs 追加 aar/jar（拷贝+去重）
│   │   ├── CAndroidRes.cs        # res/values/strings.xml 追加；proguard 追加
│   │   └── CAndroidEnv.cs        # SDK/NDK/JDK 路径校验与提示模型
│   └── iOS/
│       ├── CIosPlist.cs          # plist XML 键值注入（幂等，数组/字典/字符串/布尔）
│       ├── CIosFrameworks.cs     # 系统 framework / .framework/.a 描述模型
│       ├── CIosBuildSettings.cs  # Build Settings 键值模型
│       ├── CIosCapability.cs     # Capability 枚举与参数模型
│       └── CIosFiles.cs          # 追加源码/资源文件描述（拷贝进工程 + 入 target）
├── Editor/                       # Unity 适配层（薄）
│   ├── CoffeeBean.Build.Editor.asmdef   # references: Runtime + UnityEditor
│   ├── ExportBuildCallbacks.cs   # IPostGenerateGradleAndroidProject / iOS 回调 → CExportSession
│   ├── EditorAndroid/
│   │   ├── CoffeeBean.Build.EditorAndroid.asmdef   # 引用 UnityEditor.Android（平台模块）
│   │   ├── AndroidManifestToXml.cs   # 把 CAndroidManifest 模型落到文件
│   │   └── AndroidEnvCheck.cs        # 读 PlayerSettings/Preferences 做环境校验 UI
│   ├── EditoriOS/
│   │   ├── CoffeeBean.Build.EditoriOS.asmdef      # 引用 UnityEditor.iOS.Extensions(.Xcode)
│   │   ├── PbxProjectAdapter.cs     # PBXProject 封装（加 framework/file/property）
│   │   ├── CapabilityAdapter.cs     # ProjectCapabilityManager 封装
│   │   └── PlistAdapter.cs          # PlistDocument 封装（mac 构建机）
│   ├── CExportConfigAsset.cs        # ScriptableObject 包壳（序列化 CExportConfig）
│   └── CExportConfigWindow.cs       # Editor 窗口（Hub 注册工具卡片）
├── Samples~/NativeExportDemo/
└── Tests/                            # CoffeeBean.Build.Tests.asmdef（TestAssemblies）
```

> 平台 asmdef（EditorAndroid/EditoriOS）只在安装对应 Build Support 时编译——需把包引用声明为可选。
> Unity 无原生"可选 asmdef 引用"：方案是这两个 asmdef 走 **Version Defines / 反射注册**，
> 或按 `Assets/Plugins` 惯例让用户按平台安装。**实施时先用 unity_reflect 探测当前编辑器里
> `UnityEditor.Android` 与 `UnityEditor.iOS.Xcode` 程序集的确切名称/可用性再定**（见 §10 风险）。

---

## 4. 导出后处理管线（核心模型）

```
[构建事件触发]
   │  (导出 Android Gradle 工程 / 导出 iOS Xcode 工程成功之后、构建产物归档之前)
   ▼
CExportRunner.Run(platform, exportRoot, config)
   │
   ├─ 1. 定位工程：Android → 找 launcher/unityLibrary 根；iOS → Unity-iPhone.xcodeproj
   ├─ 2. 环境前置校验（AndroidEnvCheck：SDK/NDK/JDK；缺失→可配置 abort 或警告）
   ├─ 3. 按序执行平台步骤（每步：记录→执行→校验幂等→异常即中止，报步骤+文件+行）
   │     Android 步骤链：Manifest → gradle(settings/build) → gradle.properties
   │                    → libs → res/strings → proguard
   │     iOS 步骤链：   Info.plist → frameworks/libs → Build Settings
   │                    → capabilities/entitlements → 追加文件 → (v0.2 pods)
   ├─ 4. 会话汇总：写入 <exportRoot>/CoffeeBeanExport.log（各步骤改动清单）
   └─ 5. 完成回调（供 CI 读取结果）
```

### 4.1 步骤接口

```csharp
namespace CoffeeBean
{
    /// <summary>导出定制步骤：一个步骤负责一类文件/一类注入。</summary>
    public interface IExportStep
    {
        string Id { get; }                    // 唯一 id（幂等表 & 日志用）
        bool IsActive(CExportSession s);      // 按平台/配置开关决定是否执行
        void Execute(CExportSession s);       // 注入逻辑；失败抛 CExportException
    }

    /// <summary>一次导出会话：上下文 + 结果。</summary>
    public sealed class CExportSession
    {
        public CExportPlatform Platform;      // Android / iOS
        public string ExportRoot;             // 导出工程根目录（绝对路径）
        public CExportConfig Config;          // 合并后的配置
        public CExportLog Log;                // 步骤改动清单
        // 幂等：记录已注入的 signature（manifest 节点 key、gradle 行 hash、
        //       plist 键、framework 名、文件目标路径），重复即跳过
        internal HashSet<string> AppliedKeys;
        public bool WasApplied(string key);
        public void MarkApplied(string key);
    }
}
```

### 4.2 触发（Unity 构建回调，适配层职责）

调研结论（AdMob/OneSignal/Firebase 均用 `[PostProcessBuild]` + `#if UNITY_IOS` 条件编译做 iOS 后处理，
Android 侧行业标准是 EDM4U 的 gradle 模板注入）：

| 平台 | 首选回调 | 说明 |
|------|----------|------|
| iOS | `[PostProcessBuild(BuildTarget.iOS)]` 静态方法（`UnityEditor.Callbacks`） | 导出 Xcode 工程后触发，`path`=Xcode 工程根；`#if UNITY_IOS` 包裹避免无 iOS 模块时编译；适配层内统一入口 |
| Android（导出工程模式） | `IPostGenerateGradleAndroidProject.OnPostGenerateGradleAndroidProject(path)` | 仅导出 Gradle 工程/构建时工程生成后触发，path=gradle 工程根 |
| Android（直接出包模式） | `[PostProcessBuild]` 兜底 | 无法访问中间 gradle 工程时跳过工程注入并记日志 |

> 回调接口的确切签名以 **Unity 6000.0.71f1 编辑器反射结果为准**（实施第一步验证），
> 适配层集中封装，业务 API 稳定；iOS 后处理代码一律 `#if UNITY_IOS`（或平台 asmdef）防未装模块报错。

---

## 5. Android 平台设计（导出 Android Studio 工程）

Unity 6 导出 Android Studio 工程典型结构（`Export Project` 勾选时）：

```
<exportRoot>/
├── settings.gradle / build.gradle / gradle.properties
├── launcher/                       # 壳工程（Application 模块）
│   ├── build.gradle
│   └── src/main/AndroidManifest.xml
└── unityLibrary/                   # Unity 引擎模块
    ├── build.gradle
    ├── libs/                       # *.aar / *.jar
    └── src/main/
        ├── AndroidManifest.xml
        └── res/values/strings.xml
```

> 注：Unity 导出的 **merged manifest** 行为——`unityLibrary` 的 manifest 与 `launcher` 的 manifest
> 在 gradle 打包时再合并；导出后处理阶段工程里是**两份源 manifest**，注入时按配置选择
> 目标（默认两处都处理，或指定 `targetManifest: launcher|unityLibrary|both`）。

### 5.1 Manifest 注入器（CAndroidManifest）

用 `XmlDocument`（保留命名空间 `android:`/`tools:`），全部**幂等**：先查后插，节点签名 = 标签+关键属性组合。

| 能力 | API | 注入点 |
|------|-----|--------|
| 权限 | `EnsurePermission(name)` | `<manifest>` 下 `<uses-permission android:name>`，已存在跳过 |
| feature | `EnsureUsesFeature(name, required)` | `<uses-feature>` |
| meta-data | `EnsureApplicationMetaData(key, value)` | `<application>` 下 `<meta-data>`（按 name 去重，同 key 覆盖值） |
| activity | `EnsureActivity(name, attrs)` | 按 `android:name` 去重；可选 `android:exported`/launcher 调整 |
| service/receiver/provider | 同上模式 | 按 name 去重，`tools:replace` 冲突标记可配 |
| application 属性 | `SetApplicationAttribute(attr, value)` | `android:name`(自定义 Application)/label/theme/allowBackup 等 |
| 命名空间 | 自动 | 首插 android 节点时补 `xmlns:android`；用 tools 时补 `xmlns:tools` + `tools:replace` 可选 |

Manifest 配置示例（JSON 片段）：

```jsonc
{
  "android": {
    "manifest": {
      "permissions": ["android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"],
      "applicationMetaData": { "coffeebean_channel": "googleplay" },
      "applicationAttributes": { "name": "com.my.CustomApp" }
    }
  }
}
```

### 5.2 Gradle 注入器（CGradleFile）

build.gradle 是**脚本不是 XML** → 采用**文本锚点注入**：
- 锚点表：`dependencies {` / `repositories {` / `android {` / `defaultConfig {` / `signingConfigs {` / `buildTypes {`
- 在锚点块**首行后**插入行（保持缩进可配），已存在相同行（trim 后相等）跳过
- 支持把 `\n` 多行片段插入（如整段 `signingConfigs { release { ... } }`）

| 能力 | 示例注入行 |
|------|-----------|
| 依赖 | `implementation 'com.some.sdk:x:1.0.0'` / `implementation files('libs/xx.aar')` |
| 仓库 | `maven { url 'https://myrepo.com' }` |
| signing | `signingConfigs { release { storeFile file('xx.keystore'); ... } }` + `buildTypes.release.signingConfig signingConfigs.release` |
| flavor/维度 | `flavorDimensions "channel"` / `productFlavors { googleplay { } }` |
| 编译选项 | `compileOptions { sourceCompatibility JavaVersion.VERSION_11 }` |

配置示例：

```jsonc
{
  "android": {
    "gradle": {
      "targetFiles": ["unityLibrary/build.gradle", "launcher/build.gradle"],
      "anchor": "dependencies {",
      "lines": [
        "implementation 'com.android.support:multidex:1.0.3'",
        "implementation(name: 'mysdk', ext: 'aar')"
      ]
    }
  }
}
```

### 5.3 gradle.properties（CGradleProperties）

`key=value` 幂等读写：存在同 key 更新值，缺 key 追加。

```jsonc
{
  "android": {
    "gradleProperties": {
      "android.useAndroidX": "true",
      "android.enableJetifier": "false",
      "org.gradle.jvmargs": "-Xmx2048m"
    }
  }
}
```

### 5.4 环境变量 / 构建环境（CAndroidEnv）—— 对应"设置环境变量"

构建机侧三类"环境"，导出时校验并可按需写入工程配置：

1. **SDK/NDK/JDK 路径**：读 `ANDROID_HOME` / `ANDROID_NDK_HOME` / `JAVA_HOME` 与 Unity `EditorPrefs`（Android SDK 路径）；
   `CExportEnvReport` 输出每项 found/missing；缺失项按 `env.policy = abort|warn` 处理
2. **写入工程侧**：`local.properties`（`sdk.dir=...`）——gradle 构建用（Unity 通常已写，缺则补）
3. **CI 场景**：支持 `-executeMethod CoffeeBean.ExportCli.Run -exportRoot ... -configPath ...` 批处理入口，
   导出后读 `CoffeeBeanExport.log` 判定成功（供 Jenkins/GitHub Actions 用）

### 5.5 libs 追加（CAndroidLibs）

- 源：配置里指向的 aar/jar 资产路径（`Assets/...` 或绝对路径）
- 目标：`unityLibrary/libs/`（默认）与/或 `launcher/libs/`
- 幂等：按文件名去重（同名同字节跳过）；拷贝后可选自动在目标 gradle 的 `dependencies {` 追加 `implementation files('libs/xxx.aar')`
- **与 Unity `Assets/Plugins/Android` 的关系**：静态库仍建议放 `Plugins/Android`（Unity 自动入 libs）；
  本模块的 libs 追加用于**动态/按渠道**决定放不放的场景（同一份代码不同导出注入不同库）
- **`.androidlib` 模式（OneSignal/AdMob 实证）**：带源码+manifest 的 Android library 建议组织成
  `Plugins/Android/*.androidlib` 目录（Unity 自动按 aar 编译合并、manifest 自动参与合并）；
  本模块 libs 追加的是**无源码纯二进制**（.aar/.jar）场景

### 5.6 res / proguard（CAndroidRes）

- `unityLibrary/src/main/res/values/strings.xml`：`<string name=...>` 幂等追加（app_name 多语言覆盖）
- `launcher/src/main/res/...` 同理（配置 target）
- proguard：`unityLibrary/proguard-unity.txt`（或 launcher）末尾追加 keep 规则（按行去重）

---

## 6. iOS 平台设计（导出 Xcode 工程）

导出目标（mac 构建机）：

```
<exportRoot>/
├── Unity-iPhone.xcodeproj/          # PBXProject 修改对象
├── Info.plist                       # 键值注入对象（或由 PBX 指向的 plist）
├── UnityFramework/  …               # 两个 target：Unity-iPhone（主） + UnityFramework
└── Podfile                          # v0.2：CocoaPods
```

### 6.1 Info.plist 注入（CIosPlist）

实现双轨（与 AdMob `PListProcessor.cs` 同思路，实证见 §14）：
- **mac 构建机**：直接用 `UnityEditor.iOS.Xcode.PlistDocument` —— `ReadFromFile` → `root.SetString` /
  `root.CreateArray` → 已存在键用 `values.TryGetValue + AsArray/AsDict` 做**幂等合并** → `WriteToString` 落盘
- **Windows/纯逻辑**：内置 plist XML 读写器（测试与 dry-run 用），格式与 PlistDocument 输出兼容

| 场景 | 键 | 注入 |
|------|-----|------|
| ATT 权限弹窗 | `NSUserTrackingUsageDescription` | string（中文文案） |
| 系统权限文案 | `NSLocationWhenInUseUsageDescription` / `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` / `NSMicrophoneUsageDescription` 等 | string |
| 广告归因 | `SKAdNetworkItems` | array<dict>（`SKAdNetworkIdentifier`），按配置追加，已存在跳过 |
| 深链 | `CFBundleURLTypes` | array<dict>（`CFBundleURLSchemes`），按 scheme 去重 |
| ATS | `NSAppTransportSecurity` | dict（`NSAllowsArbitraryLoads` bool，或按域例外） |
| 广告标识 | `GADApplicationIdentifier`（AdMob）等 SDK 专属键 | 通用 string/dict 注入即可覆盖 |
| 自定义 | 任意 `key/value/type` | 通用 `SetValue(path, value, type)`：`dict > array > dict` 路径定位 |

幂等：key 存在即按 `policy = overwrite|skip`（默认 skip；权限文案默认 overwrite 并记日志）。

### 6.2 库文件追加（CIosFrameworks）—— 对应"追加库文件"

**模型**（纯 C#，可测）：

```csharp
public enum CIosLibKind { SystemFramework, EmbeddedFramework, StaticLibrary, Xcframework, SourceFile, ResourceBundle }

public sealed class CIosLibEntry
{
    public string SourcePath;        // 资产路径（.framework/.xcframework/.a/.m/.swift/.bundle）
    public CIosLibKind Kind;
    public bool Embed;               // 动态 framework 是否 Embed & Sign
    public string[] LinkerFlags;     // 静态库附加 -ObjC / -lz / -lc++ 等
    public string[] Frameworks;      // 依赖的系统 framework（自动加）
    public string[] WeakFrameworks;  // 弱链接
}
```

| 能力 | 落地方式（适配层） | 说明 |
|------|-------------------|------|
| 系统 framework | `PBXProject.AddFrameworkToProject(target, name, weak)` | AdSupport/StoreKit/AppTrackingTransparency/WebKit/UserNotifications/AuthenticationServices/AVFoundation… |
| 三方动态 framework | 拷贝进工程 → AddFile → AddFileToBuild(target, phase, embed=true) | 设置 **Embed Frameworks** 阶段 |
| 三方静态库 `.a` | 拷贝进工程 → AddFile → AddFileToBuildWithFlags（`-ObjC`…） | UnityFramework target |
| `.xcframework` | AddFile（Xcode 12+ 支持，按 slice 由 Xcode 选） | v0.1 支持拷贝+注册，编译选项后续调 |
| 源码/资源文件 | 拷贝 → AddFile → AddFileToBuild 到对应 target | .m/.swift/.h/.mm/.bundle |
| target 选择 | `GetUnityMainTargetGuid` / `GetUnityFrameworkTargetGuid` 或两者 | 配置 `target = main|framework|both` |

幂等：按文件名 + 目标 target 查 PBX 已有 file 引用；重复跳过并记录。

### 6.3 Build Settings 注入（CIosBuildSettings）—— 对应 iOS 侧"环境变量"

| 常用键 | 值示例 | 说明 |
|--------|--------|------|
| `GCC_PREPROCESSOR_DEFINITIONS` | `$(inherited) COFFEEBEAN_ADS=1` | 宏（追加，保 `$(inherited)`） |
| `OTHER_LDFLAGS` | `$(inherited) -ObjC` | 链接参数（追加） |
| `ENABLE_BITCODE` | `NO` | 部分 SDK 要求关 bitcode |
| `IPHONEOS_DEPLOYMENT_TARGET` | `13.0` | 最低系统（取 max 与 Unity 默认） |
| `SWIFT_VERSION` | `5.0` | 混 Swift 时 |
| `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` | 由 CI 注入 | 签名 |
| 任意键 | — | 通用 `SetBuildProperty(target, key, value, append|overwrite)` |

### 6.4 Capability / entitlements（CIosCapability + 适配层 ProjectCapabilityManager）

| Capability | 参数 |
|------------|------|
| Push Notifications | （含 aps-environment entitlement 自动） |
| Background Modes | modes: audio/location/remote-notification/fetch/processing |
| Sign in with Apple | — |
| In-App Purchase | — |
| Game Center / iCloud 等 | 枚举扩展 |

落地：`ProjectCapabilityManager(projectPath, target, entitlementsPath)` → Add… → `WriteToFile()`；
若工程已有 entitlements 则追加而非覆盖（读取现有 + merge，幂等）。

### 6.5 Podfile（v0.2 候选，先留模型）

`CIosPods`：生成/追加 `Podfile`（target UnityFramework do … end），记录已加 pod；执行 `pod install` 留到 v0.2（CI 环境配置差异大）。

---

## 7. 配置模型（CExportConfig）

单配置 JSON/ScriptableObject 同时描述两平台，顶层按平台分组：

```csharp
namespace CoffeeBean
{
    [Serializable]
    public sealed class CExportConfig
    {
        public bool Enable;                       // 总开关
        public AndroidSection Android;            // §5 各注入器配置
        public IosSection IOS;                    // §6 各注入器配置
        public string[] ExportEnabledFor;         // 限定构建 target（Android/iOS/空=全部）
    }
}
```

来源优先级（低→高，逐层覆盖/合并）：
1. **包内内置默认**（空配置，Enable=false）
2. **工程资产** `Assets/CoffeeBean/ExportConfig.asset`（ScriptableObject，Editor 窗口编辑，可 JSON 导入导出）
3. **代码注册**：`CExportRunner.RegisterConfig(config, priority)`（多 SDK/渠道各自追加自己的片段）

渠道/后端差异化：同 SDK 不同渠道 → 建议多份配置资产，CI `-configPath` 指定（§5.4）。

---

## 8. 可扩展性（SDK 集成方怎么用）

```csharp
// 例：某广告 SDK 的导出定制（写在游戏工程或独立 provider 包 Editor 下）
[ExportStep]   // 属性注册，管线启动时反射收集（与 Core Hub 工具注册同思路）
public sealed class MySdkAndroidStep : IExportStep
{
    public string Id => "myadsdk.android";
    public bool IsActive(CExportSession s) => s.Platform == CExportPlatform.Android;
    public void Execute(CExportSession s)
    {
        s.Config.Android.Manifest.EnsurePermission("android.permission.INTERNET"); // 或直接操作模型
        s.Config.Android.Gradle.AddAnchorLines("dependencies {", new[] { "implementation 'com.my:ads:1.0'" });
    }
}
```

要点：`CExportSession.Config` 在执行链内**可变** → 前序步骤（SDK 声明）的注入会被后续落盘步骤统一应用；步骤顺序 = 注册顺序 + 显式 `Order`（落盘步骤 `Order=10000` 恒在最后）。

---

## 9. 依赖与集成

- 依赖：`com.coffeebean.tools`（CLog/CJson/路径工具）；Core 可选（Bridge 模块标记，COFFEEBEAN_CORE 宏）
- Hub：Editor 工具窗口 `CExportConfigWindow`（读/写/试跑 dry-run）经 `CoffeeBeanToolAttribute` 注册进 Core Hub（**不注册任何 Window/CoffeeBean 子菜单**，遵守 Hub 规则）
- CI：`CoffeeBean.ExportCli.Run -exportRoot -configPath` 静态入口（无窗口运行）
- Sample：`Samples~/NativeExportDemo`（含一份最小配置资产 + 文档化步骤示例 + 假导出目录演练）
- **与 EDM4U（External Dependency Manager for Unity）互补定位**：EDM4U 管"第三方 maven/gradle 依赖与 iOS CocoaPods 解析"
  （SDK 写 `*.Dependencies.xml` 声明即可），本模块管"工程文件内容定制"（manifest/plist/build settings/文件入 target/环境）。
  若检测到 EDM4U 已安装，配置资产中提示依赖类诉求走 EDM4U（避免 gradle 依赖双份注入冲突）

---

## 10. 风险与注意事项（实施时验证）

1. **Unity 版本 API 差异（最高优先）**：`IPostGenerateGradleAndroidProject` / iOS 回调 / `PBXProject` / `ProjectCapabilityManager` / `PlistDocument` 在 6000.0.71f1 的确切命名空间与程序集名 → 实施第一步用编辑器反射确认，集中在适配层，业务 API 稳定
2. **平台模块可选安装**：EditorAndroid/EditoriOS asmdef 引用平台程序集，未装对应 Build Support 时编译策略（Version Defines 或按平台 asmdef + 安装说明），避免用户没装 Android 模块就报错
3. **iOS 只能在 mac 导出 Xcode 工程**：Windows 编辑器上 iOS 回调不触发；注入核心逻辑仍可在 Windows EditMode 测试（fake 工程 + 纯 XML/文本）
4. **gradle 模板 vs 后处理**：静态模板用 Unity `Assets/Plugins/Android/*Template.gradle` 更优时文档引导；后处理处理动态场景，两者不互斥
5. **幂等是关键**：重复导出同工程必须零重复节点/行/库；所有注入器自带"先查后插"签名
6. **manifest 合并冲突**：注入 activity 的 `android:exported`/`tools:replace` 需谨慎，配置暴露显式覆盖
7. **不破坏 Unity 再导出**：只改导出产物目录；不动 `Assets/`（除用户显式放 `Plugins/` 的静态资产）
8. **日志/失败语义**：任何注入失败 → `CExportException(步骤, 文件, 原因)` → 中止构建回调返回前抛出（Unity 显示构建失败）；dry-run 模式只算不改

---

## 11. 测试与验证计划（EditMode，不打真构建）

用 **fake 导出工程**（测试内构造最小目录树）驱动管线：

| 测试组 | 覆盖 |
|--------|------|
| Manifest 注入 | 权限/组件/meta-data 插入；**重复执行不重复**；xmlns/tools 自动；application 属性覆盖 |
| Gradle 注入 | 锚点插行、已存在跳过、多行片段、多目标文件 |
| gradle.properties / local.properties | key 更新与追加、CI 环境报告 |
| libs 追加 | 拷贝+去重+自动依赖行 |
| plist 注入 | string/array/dict 键、权限文案覆盖、SKAdNetwork 去重、深链 scheme 去重 |
| framework 模型 | 系统/动态/静态/源文件条目解析、embed 标志 |
| 管线 | 步骤顺序、Order、开关、异常中止、dry-run、session 幂等表、日志 |
| 配置合并 | JSON→模型、多源覆盖优先级 |
| 期望产物快照 | （借鉴 EDM4U `ExpectedArtifacts` 模式）预置"注入后应得"的完整文件文本，注入后逐字符对比 |
| Unity 回调适配层 | （如 Editor 环境允许）触发一次假导出走完整链路 |

**发布前验收**：dev 工程全量 EditMode 绿 + Sample 可打开 + 真机/模拟器验证留到游戏工程接入轮。

---

## 12. 里程碑

| 版本 | 内容 |
|------|------|
| v0.1.0 | §2 范围全部（Manifest/gradle/gradle.properties/libs/res/env + plist/framework/BuildSettings/基础 Capability/文件入 target）；Sample + 测试；发布流程全套 |
| v0.2 候选 | CocoaPods 执行、flavor 矩阵 UI、xcframework 细节、entitlements merge 增强、CI 报告格式、其他平台（若需要） |

---

## 13. 待确认事项

1. 模块名：`com.coffeebean.build`（推荐）/ `com.coffeebean.export` / `com.coffeebean.native`？
2. 单包（推荐）还是 Android/iOS 拆两包？
3. v0.1.0 范围是否照 §2；有无优先要加的注入类型（如多渠道、签名、Podfile 执行提前）？

---

## 14. 开源参考调研（2026-09）

> 目的：确认业界成熟做法，校准触发回调/注入 API/测试策略。已确认真实仓库与关键源码。

### 14.1 参考项目清单

| 项目 | Stars | 与本模块的关系 | 关键实证 |
|------|-------|----------------|----------|
| [googlesamples/unity-jar-resolver](https://github.com/googlesamples/unity-jar-resolver)（EDM4U，Google 官方） | 1472 | Android/iOS **第三方依赖解析**标准件 | gradle 模板注入（mainTemplate/settingsTemplate，含 `DISABLED` 命名开关、Unity 版本分支）；iOS CocoaPods；**期望产物快照测试**（ExpectedArtifacts） |
| [googleads/googleads-mobile-unity](https://github.com/googleads/googleads-mobile-unity)（AdMob 官方） | 1547 | iOS plist / Android manifest 注入直接范本 | `PListProcessor.cs`：`[PostProcessBuild]` + `#if UNITY_IOS`；`PlistDocument.ReadFromFile → SetString/CreateArray → WriteToString`；SKAdNetworkItems 幂等数组合并；ScriptableObject 承载 appId/权限文案；空配置**中止构建** |
| [firebase/firebase-unity-sdk](https://github.com/firebase/firebase-unity-sdk)（Firebase 官方） | 320 | 大规模多 SDK 依赖管理范本 | 全部经 EDM4U `*.Dependencies.xml` 声明 android 依赖/iOS pods+frameworks；本模块与其互补 |
| [OneSignal/OneSignal-Unity-SDK](https://github.com/OneSignal/OneSignal-Unity-SDK) | 228 | iOS framework/capability + Android manifest | `com.onesignal.unity.ios/Editor/BuildPostProcessor.cs` + `PBXProjectExtensions.cs`（**PBX 封装为扩展方法**）；Android 用 `.androidlib` 目录自带 manifest；example 含 `SigningPostProcessor.cs`（签名注入） |
| [facebook/facebook-sdk-for-unity](https://github.com/facebook/facebook-sdk-for-unity) | 505 | 老牌 plist/framework 后处理参考 | 历史实现覆盖 plist 键注入与 framework 追加的完整边界案例 |
| [TylerTemp/SaintsBuild](https://github.com/TylerTemp/SaintsBuild) | 21 | 多平台打包工具视角 | android/ios/windows/mac 打包 + 后处理编排的整体结构参考 |
| [MartinGonzalez/unity-android-manifest-placeholders-resolver](https://github.com/MartinGonzalez/unity-android-manifest-placeholders-resolver) | 1 | Manifest 占位符注入思路 | `${var}` 占位符 → build.gradle 值替换（manifest 动态化的另一条路） |

### 14.2 结论与本设计校准

1. **iOS 触发回调**：行业主流 = `[PostProcessBuild]` 静态方法 + `#if UNITY_IOS`（AdMob/OneSignal 均如此），
   而非 `IPostGenerateXcodeProject` 接口 → 本设计 §4.2 已按此校准
2. **plist 注入**：`UnityEditor.iOS.Xcode.PlistDocument` 的 `root.SetString/CreateArray/AsArray` + `WriteToString`
   是标准 API；幂等靠"key 已存在 → 取数组/字典合并" → §6.1 已校准
3. **Android 依赖**：业界几乎都交给 EDM4U（gradle 模板 + `*.Dependencies.xml`），SDK 自身很少直接改 build.gradle
   → 本模块**不重复造依赖解析**，专注工程内容定制（manifest/文件/属性/环境），并在 §9 声明互补关系
4. **配置承载**：ScriptableObject（AdMob `GoogleMobileAdsSettings`）是通用模式 → 本设计 §7 用
   `CExportConfig` ScriptableObject 包壳 + JSON 导入导出
5. **失败语义**：AdMob 空 appId 直接 `BuildFailedException` 中止 → 本设计异常中止构建一致
6. **测试方法**：EDM4U 用期望产物快照对比（含版本分支、DISABLED 开关矩阵）→ §11 测试计划已加
7. **Android 库携带**：`.androidlib`（自动编译 aar + manifest 合并）是带源码库的推荐形态，本模块只补纯二进制 libs 场景
