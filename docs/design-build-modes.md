# CoffeeBean 游戏构建模式规划（测试包 vs 正式包：测试工具 / 日志策略）

> 版本：v0.1（草案，待确认）
> 状态：待确认后实施

---

## 1. 背景与目标

游戏发布形态通常分几类包：**开发包（每天给策划/程序）**、**QA/验收包**、**正式/商店包（Release）**。
诉求（本规划要解决的）：

1. **测试包**：内置测试工具 —— 游戏内控制台（日志查看）、作弊命令（给钱/解锁/切场景）、调试面板，方便日常验证
2. **正式包**：
   - **禁止测试工具**（代码不进包：安全——防反编译作弊、防泄露内部命令；体积、启动性能）
   - **关闭日志**（防信息泄露到设备日志；去掉字符串拼接开销）

现状盘点（已实现模块）：
- `com.coffeebean.tools` → `CLog`：静态门面 + **运行时** `InfoEnabled/WarningEnabled/ErrorEnabled` 三个开关（无编译期剥离，调用处字符串仍会构造）
- `com.coffeebean.debug` → `CDebug`（作弊命令门面，静态构造注册 help/clear）、`CDebugConsole`（IMGUI 悬浮窗，MonoBehaviour 懒创建，日志捕获/过滤/命令输入）、`CDebugCommandRegistry`（纯逻辑注册表）
- `com.coffeebean.core` → `CoffeeBeanDefineInstaller`（[InitializeOnLoad] 自动往 PlayerSettings 写 `COFFEEBEAN_CORE` 宏的机制，可参考）
- Unity 内置宏：`DEVELOPMENT_BUILD`（勾 Development Build 时定义）、`UNITY_ASSERTIONS`（Editor + Development Build）、`Debug.isDebugBuild`（运行时）

**设计原则**：默认安全态 —— 正式包 = **少 define**（不定义开发宏），这样即使漏配也不会把工具带进 Release；开发宏只在编辑器/测试包显式存在。

---

## 2. 构建模式定义

### 2.1 两个维度

| 维度 | 取值 | 说明 |
|------|------|------|
| 构建目标 | **Development** / **QA** / **Release** | 测试工具与日志的开关主维度 |
| 渠道 | GooglePlay / AppStore / 国内渠道… | SDK/打包差异（广告、内购配置等），**不参与本设计**；宏体系预留命名空间 |

### 2.2 推荐包形态

| 包 | Development Build | QA | Release |
|----|:---:|:---:|:---:|
| 游戏内控制台（CDebugConsole） | ✅ | ✅（可选关） | ❌ 代码不进包 |
| 作弊命令注册（CDebug.Register） | ✅ | ✅ | ❌ 调用点被编译器移除 |
| 调试 HUD / 统计面板入口 | ✅ | ✅ | ❌（或隐藏） |
| Info/Warn 日志 | ✅ | ✅ | ❌（编译期剥离） |
| Error 日志 | ✅ | ✅ | ✅（建议打点上送） |
| 断言 | ✅ | ✅ | ❌（UNITY_ASSERTIONS 自动） |

### 2.3 Unity 侧映射
- **Development 包**：Build Settings 勾 *Development Build*（自动带 `DEVELOPMENT_BUILD`/`UNITY_ASSERTIONS`）
- **Release 包**：不勾 Development Build
- **编辑器**：恒为开发态（`UNITY_EDITOR`），测试工具在编辑器可随时用，与"要打什么包"解耦

---

## 3. 编译期宏体系（核心）

> 宏名统一 `COFFEEBEAN_*` 前缀；**Release 全部不定义**（默认安全态）。

| 宏 | 定义于 | 作用 | 消费者 |
|----|--------|------|--------|
| `COFFEEBEAN_DEV_TOOLS` | 编辑器、Development/QA 构建 | 测试工具（控制台/作弊命令/调试面板）编译开关；**未定义 → 相关类型/调用点不进包** | debug 模块、ui 调试入口、游戏 HUD |
| `COFFEEBEAN_LOG` | 编辑器、Development/QA 构建 | Info/Warn 日志剥离（`[Conditional]` → 调用点连同参数字符串一起消失）；**未定义 → 普通日志零成本零输出** | tools 的 CLog |
| （沿用）`COFFEEBEAN_CORE` | core Installer 自动 | 模块 Bridge 集成开关 | 各模块 Bridge |
| （Unity 内置）`DEVELOPMENT_BUILD` | Development Build | 运行时 `Debug.isDebugBuild` | CGameBuild 运行时判定 |
| （Unity 内置）`UNITY_ASSERTIONS` | Editor + Development | 断言编译开关 | 业务断言 |

### 3.1 宏怎么设置（工程实践，重要）
Unity 没有"按构建配置自动宏"；编辑器打开时用的是**当前 BuildTargetGroup 的 symbols**。
推荐三选一（按工程规模）：

- **A（推荐，CI/命令行）**：构建脚本 `-executeMethod` 里按目标设置/清理 symbols：
  ```
  打 Development/QA：PlayerSettings.SetScriptingDefineSymbols(Android, 旧 + "COFFEEBEAN_DEV_TOOLS;COFFEEBEAN_LOG")
  打 Release：先移除这两个宏再构建
  ```
  优点：Release 构建环境保证无宏；缺点：编辑器手工点 Build 需自己加宏（见 B）
- **B（编辑器日常）**：core `CoffeeBeanDefineInstaller` 扩展或工程内 [InitializeOnLoad]：
  编辑器打开时若**非 Release 意图**就加上 `COFFEEBEAN_DEV_TOOLS;COFFEEBEAN_LOG`。
  注意：这样 Release 包若也在本机用同一 symbols 打，会被 Installer 污染 → **Release 构建必须走 A 的清宏**。
  折中：Installer 只在 `UNITY_EDITOR && !COFFEEBEAN_RELEASE` 下追加？宏作用于编译，编辑器和打包共用 symbols，无法区分"打包瞬间"。
  → 结论：编辑器常开宏（体验好），**正式打包固定走构建脚本/CI 清宏**（把"Release 不带宏"变成发布流程硬约束）
- **C（Unity 6 Build Profile）**：Unity 6 的 Build Profile 支持按 Profile 配置 scripting define symbols，天然分离
  （一个工程多 Profile：Dev/QA/Release 各一份，Release Profile 不含宏）——**最推荐**，文档按此主线写

### 3.2 编辑器内切换（开发辅助，可选）
core Hub 或 tools 提供一个"构建模式"小工具（Editor）：一键在 Dev/QA/Release symbols 之间切换 + 提示。
放 v0.2 候选，非必需。

---

## 4. 日志策略（tools 改造）

### 4.1 CLog 剥离 Info/Warn（正式包零日志）
```csharp
[Conditional("COFFEEBEAN_LOG")]      // 宏未定义 → 所有调用点被编译器移除（参数不求值）
public static void Info(string tag, string message) { if (InfoEnabled) Debug.Log(...); }
[Conditional("COFFEEBEAN_LOG")]
public static void Warn(string tag, string message) { ... }
// Error 保留无条件（正式包错误仍要可见/可上送）
public static void Error(string tag, string message) { ... }
public static void Error(string tag, string message, Exception e) { ... }
```
- 效果：Release（无 `COFFEEBEAN_LOG`）→ `CLog.Info("IAP", $"购买成功 {id}")` 这类调用**整行消失**，
  不产生字符串、不产生调用——比运行时 bool 关更彻底
- 兼容：Editor/开发构建定义了宏 → 行为与现在一致（运行时开关仍有效，可再按 tag/级别细化）
- ⚠️ 破坏性说明：现有 0.x 用户若升级且**没**在 symbols 里加 `COFFEEBEAN_LOG`，普通日志会消失
  → 发布时在 CHANGELOG/README 显著说明；`COFFEEBEAN_LOG` 也建议由 core Installer 默认补上（Editor 态）

### 4.2 正式包 Error 去向（与 telemetry 组合，游戏工程侧）
- Release 建议 `Debug.unityLogger.filterLogType = LogType.Error`（只留错误）
- 错误除本地外，可经 `CTelemetry.Track("error", tag/message)` 上送（业务侧封装，tools 不依赖 telemetry）

---

## 5. 测试工具策略（debug 模块改造，核心）

### 5.1 目标：Release 里"测试工具代码不存在"
作弊命令 = 攻击面（改钱/解锁/切服的命令若留在包里，可被反编译调用）。方案：

- **CDebug.Register / 控制台入口**：`[Conditional("COFFEEBEAN_DEV_TOOLS")]`
  - `Register` 是 void → 可直接 Conditional：Release 下业务侧所有 `CDebug.Register(...)` 调用点消失，
    连委托都不构造 —— 作弊逻辑天然不进包（业务无需手写 #if）
  - `Unregister` void 同理
- **CDebugConsole**（IMGUI 控制台类）：`#if COFFEEBEAN_DEV_TOOLS` 包裹 → Release 无此类型
- **CDebug 其余 API**（命令查询/执行等仅开发用 API）：随宏包裹或保留空实现由 Conditional 控制
- 游戏侧 HUD 上的"打开控制台"按钮：`#if COFFEEBEAN_DEV_TOOLS` 或运行时 `CGameBuild.HasDevTools`

### 5.2 新增运行时门面 CGameBuild（放 tools，零依赖，全员可引）
```csharp
namespace CoffeeBean
{
    /// <summary>构建模式运行时判定。</summary>
    public static class CGameBuild
    {
        /// <summary>是否编辑器（开发态恒真）。</summary>
        public static bool IsEditor => Application.isEditor;

        /// <summary>是否 Development Build（Unity 判定）。</summary>
        public static bool IsDevelopmentBuild => Debug.isDebugBuild;

        /// <summary>测试工具是否编译进包（= 宏定义；编辑器/开发包 true，Release false）。</summary>
        public static bool HasDevTools =>
#if COFFEEBEAN_DEV_TOOLS
            true;
#else
            false;
#endif

        /// <summary>普通日志是否编译进包（= COFFEEBEAN_LOG）。</summary>
        public static bool HasLogging =>
#if COFFEEBEAN_LOG
            true;
#else
            false;
#endif

        /// <summary>开发期专用操作：Release 下是 no-op（供不适合 Conditional 的场景）。</summary>
        public static void DevOnly(Action action)
        {
#if COFFEEBEAN_DEV_TOOLS
            action?.Invoke();
#endif
        }
    }
}
```
用途：非敏感 UI 显隐用 `HasDevTools`；敏感操作用 `CDebug.Register`（Conditional 更彻底）或 `DevOnly`。

### 5.3 ui 模块调试入口（统计面板等）
- 运行时打开入口包 `#if COFFEEBEAN_DEV_TOOLS` 或判断 `CGameBuild.HasDevTools`（按数据敏感度选）
- 统计面板类本身无害可留包内（数据收集非作弊面），但入口只在 dev 显示

---

## 6. 模块改动清单（实施范围，待确认）

| 模块 | 改动 | 版本建议 |
|------|------|----------|
| `com.coffeebean.tools` | ① CLog：Info/Warn 加 `[Conditional("COFFEEBEAN_LOG")]`（Error 保留）；② 新增 `CGameBuild` | 0.5.0 → 0.6.0（Conditional 属行为变化；加说明） |
| `com.coffeebean.debug` | ① `CDebug.Register/Unregister` 加 `[Conditional("COFFEEBEAN_DEV_TOOLS")]`；② `CDebugConsole` 类 `#if COFFEEBEAN_DEV_TOOLS`；③ 其余 API 整理；④ README 宏说明 + Sample 演示 | 0.1.1 → 0.2.0 |
| `com.coffeebean.core` | （可选）Installer 扩展：Editor 态自动补 `COFFEEBEAN_DEV_TOOLS;COFFEEBEAN_LOG` | 0.1.41 → 0.1.42 |
| `com.coffeebean.ui` | 调试面板入口按宏（v0.2 候选，可后置） | — |
| 游戏工程 | 构建脚本/Profile 管宏 + 启动按模式初始化（见 §7） | — |

> Conditional 特性注意：`[Conditional]` 方法**不能有返回值**（Register/Unregister/Info/Warn 均 void，兼容）；
> 宏未定义时连实参表达式都不求值（委托不 new、字符串不拼）——这正是"正式包彻底禁止"的机制保障。

---

## 7. 游戏工程接入步骤（以 IdleMedievalLife 为例）

1. **建构建 Profile/脚本**（Unity 6 Build Profile 或 `-executeMethod`）：
   - Dev/QA Profile symbols += `COFFEEBEAN_DEV_TOOLS;COFFEEBEAN_LOG`
   - Release Profile：不包含这两个宏（构建前脚本再清一次做硬保险）
2. **启动代码**（首个场景）：
   ```csharp
   CLog.InfoEnabled = true;                       // 开发期运行时细化（宏之外的第二道）
   if (!CGameBuild.HasDevTools) { /* Release：Error 上送 hook 等 */ }
   #if COFFEEBEAN_DEV_TOOLS
   CDebug.Register("goto", "跳场景", args => SceneManager.LoadScene(args[0]), 1);
   CDebug.Register("add_gold", "加金币", args => GameSave.AddGold(int.Parse(args[0])), 1);
   #endif
   ```
   之后 Release 构建：以上代码整段消失
3. **HUD 入口**：开发按钮 `#if COFFEEBEAN_DEV_TOOLS` 或 `if (CGameBuild.HasDevTools)` 显示
4. **验证清单**：
   - Development 包：控制台可开、作弊命令可执行、日志齐全
   - Release 包（构建后用工具查）：apk/aab 内**无** `CDebugConsole`/`CoffeeBean.Debug` 命令字符串、
     反编译无 `add_gold` 等；运行无 Info/Warn 输出；Error 正常

---

## 8. 测试与验证计划

- EditMode：宏存在路径（编辑器态即开发态）下现有测试全绿（debug/tools 改动后回归）
- **宏组合编译矩阵**：单一编译集下难直接跑两套 define → 用 asmdef `defineConstraints`/`versionDefines` 或
  文档化手动验证步骤（Release 构建后查产物字符串）列入 §7.4
- debug 新增测试：`Register` 正常注册（编辑态）；`CGameBuild.HasDevTools` 为真（编辑态）
- 发布前验收：dev 全量 EditMode 绿 + Release 构建产物抽检（无工具字符串）

---

## 9. 待确认事项

1. 宏命名：`COFFEEBEAN_DEV_TOOLS` / `COFFEEBEAN_LOG` 是否合适？（或按游戏侧习惯如 `GAME_DEV`）
2. CLog 是否接受 Conditional 破坏性改动（升级后需加宏才有日志）？或仅新增剥离宏不做 Conditional？
3. 方案：tools/debug 改造发布（0.6.0 / 0.2.0）+ core Installer 扩展（0.1.42）是否照做？还是一步到位全做？
4. 是否需要一个"构建模式"模块/窗口（§3.2 编辑器一键切宏），还是构建脚本 + Profile 就够？
