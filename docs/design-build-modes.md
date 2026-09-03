# CoffeeBean 构建模式设计（Beta / Release：测试工具与日志策略）

> 版本：v0.2（已实施）
> 状态：✅ 已实施（tools v0.6.0 + debug v0.2.0 + core v0.1.42，2026-09-03 发布）

---

## 1. 目标与结论先行

| 环境 | 测试工具（作弊命令/控制台） | 日志（Info/Warn） | Error |
|------|:---:|:---:|:---:|
| **Editor（无论 Beta/Release 模式）** | 随模式（Beta 有 / Release 无） | ✅ **恒有**（开发需要） | ✅ |
| **Beta 包** | ✅ 有 | ✅ 有 | ✅ |
| **Release 包** | ❌ 代码不进包 | ❌ 编译剥离 | ✅（建议打点上送） |

三个硬性设计决策：
1. **只分 Beta / Release 两种模式**（砍掉 QA/Development 细分）；Beta = 开发宏 ON，Release = 开发宏 OFF（默认安全态）
2. **切换工具集成进 CoffeeBean Hub 窗口**（`Window/CoffeeBean`）：显示当前模式 + 一键切换，维护 PlayerSettings symbols
3. **Editor 恒日志**：日志剥离不用 `[Conditional]`（它会让 Editor 在 Release 模式下也无日志），
   改为**方法内 `#if UNITY_EDITOR || COFFEEBEAN_LOG`** —— `UNITY_EDITOR` 是平台宏，
   编辑器编译恒定义、打包 Player 不定义，天然区分"编辑器日志"与"包日志"

---

## 2. 模式定义与宏

### 2.1 两种模式

| 模式 | 用途 | symbols 里含 | 结果 |
|------|------|-------------|------|
| **Beta** | 日常开发 / 测试包 | `COFFEEBEAN_DEV_TOOLS` + `COFFEEBEAN_LOG` | 测试工具 + 日志全开 |
| **Release** | 提审/上架前验证、打正式包 | （两者都不含） | 工具剔除 + 日志剥离 |

> 默认安全态：Release = 移除开发宏。切换工具保证 Editor 里切到 Release 也只是"模拟正式包"，
> 日志仍因 `UNITY_EDITOR` 保留（见 §3.2），开发不受影响。

### 2.2 宏清单

| 宏 | 定义于 | 消费者 |
|----|--------|--------|
| `COFFEEBEAN_DEV_TOOLS` | Beta 模式 symbols | debug 模块（CDebug.Register `[Conditional]`、CDebugConsole `#if`）、游戏 HUD |
| `COFFEEBEAN_LOG` | Beta 模式 symbols | tools 的 CLog（方法体 `#if UNITY_EDITOR || COFFEEBEAN_LOG`） |
| `COFFEEBEAN_CORE` | core Installer 自动（不变） | 各模块 Bridge |
| `UNITY_EDITOR` | Unity 内置（编辑器编译恒定义） | CLog 的"Editor 恒日志"分支 |

---

## 3. 日志策略（tools 改造）

### 3.1 CLog：Info/Warn 按 `UNITY_EDITOR || COFFEEBEAN_LOG` 编译
```csharp
public static class CLog
{
    // 运行时开关保留（开发期再细化）
    public static bool InfoEnabled = true;
    public static bool WarningEnabled = true;
    public static bool ErrorEnabled = true;

    public static void Info(string tag, string message)
    {
#if UNITY_EDITOR || COFFEEBEAN_LOG
        if (InfoEnabled) Debug.Log(Format(tag, message));
#endif
    }
    public static void Warn(string tag, string message)
    {
#if UNITY_EDITOR || COFFEEBEAN_LOG
        if (WarningEnabled) Debug.LogWarning(Format(tag, message));
#endif
    }
    // Error 无条件保留（正式包错误仍可见/可上送）
    public static void Error(string tag, string message) { if (ErrorEnabled) Debug.LogError(Format(tag, message)); }
    public static void Error(string tag, string message, Exception e) { if (ErrorEnabled) Debug.LogError(Format(tag, message) + "\n" + e); }
}
```
- **Editor**（Beta 或 Release 模式）：`UNITY_EDITOR` 成立 → 日志恒有 ✅
- **Beta 包**：`COFFEEBEAN_LOG` 成立 → 日志有 ✅
- **Release 包**：两者皆不成立 → 方法体为空（调用仍在，但无 Format/无 Debug 调用，开销≈方法调用；
  若日志点在热路径且在意字符串构造，业务可用 `#if COFFEEBEAN_LOG` 包裹或仅用 Error）
- 说明：牺牲"连字符串都不构造"的极致剥离（那需要 `[Conditional]`，会连带 Editor 日志消失），换取 Editor 恒日志 —— 符合评审要求

### 3.2 运行时门面 CGameBuild（tools 新增，零依赖）
```csharp
public static class CGameBuild
{
    public static bool IsEditor => Application.isEditor;
    public static bool IsDevelopmentBuild => Debug.isDebugBuild; // Development Build 勾选

    /// <summary>测试工具是否编译进包（Beta 模式 true；Release 模式 false）。</summary>
    public static bool HasDevTools =>
#if COFFEEBEAN_DEV_TOOLS
        true;
#else
        false;
#endif

    /// <summary>日志是否编译进包（Editor 恒 true；Beta 包 true；Release 包 false）。</summary>
    public static bool HasLogging =>
#if UNITY_EDITOR || COFFEEBEAN_LOG
        true;
#else
        false;
#endif

    public static void DevOnly(Action action)
    {
#if COFFEEBEAN_DEV_TOOLS
        action?.Invoke();
#endif
    }
}
```
（Editor 切到 Release 模式时：`HasDevTools=false`、`HasLogging=true` —— 正好表达"模拟正式包工具、但日志照常"）

---

## 4. 测试工具策略（debug 模块改造）

| API | 机制 | Release 效果 |
|-----|------|-------------|
| `CDebug.Register / Unregister` | `[Conditional("COFFEEBEAN_DEV_TOOLS")]`（void，兼容） | 调用点整行消失（委托都不构造）——作弊逻辑天然不进包 |
| `CDebugConsole`（IMGUI 控制台） | 类 `#if COFFEEBEAN_DEV_TOOLS` | Release 无此类型 |
| `CDebug` 其余开发 API（查询/执行） | 随宏包裹或仅 `Register` 路径 | — |
| 游戏 HUD"打开控制台"按钮 | `#if COFFEEBEAN_DEV_TOOLS` 或 `CGameBuild.HasDevTools` | 不显示/不编译 |

- Editor Beta 模式：作弊命令可用（开发）；Editor Release 模式：无作弊命令（近似正式包，便于验收前自查）
- 非敏感 UI 显隐用 `CGameBuild.HasDevTools`；敏感操作用 `CDebug.Register`（Conditional 更彻底）

---

## 5. 模式切换工具（集成进 CoffeeBean Hub）

### 5.1 位置
**core 的 `ModuleManagerWindow`（Window/CoffeeBean Hub）** 增加"构建模式"区块（品牌区下方/状态栏上方）：

```
┌─ CoffeeBean Hub ────────────────────────────────┐
│  [构建模式: Beta]   [切到 Release]  (一键)        │
│   · Beta  ：测试工具+日志进包（开发/测试包）      │
│   · Release：工具剔除+日志剥离（提审/上架包）     │
│   · Editor 下无论模式都保留日志（UNITY_EDITOR）  │
└──────────────────────────────────────────────────┘
```

### 5.2 行为
- **当前模式判定**：读当前 BuildTargetGroup symbols —— 含 `COFFEEBEAN_DEV_TOOLS` → Beta，否则 Release
- **切换**：修改 symbols（**保留既有符号**如 `COFFEEBEAN_CORE`，仅增删两个模式宏）→ 自动触发脚本重编译
- **多目标组**：默认作用于当前选中平台组；提供"应用到所有目标组"勾选/按钮（Android/iOS/Standalone 一致）
- **旁路保护**：不做任何"安装器自动加宏"（避免 Release 打包被污染）；宏状态完全由工具与构建脚本显式管理
- **构建脚本配合**（Release 硬保险）：CI `-executeMethod` 构建前执行一次"确保 Release symbols"再打

### 5.3 core Installer 调整
`CoffeeBeanDefineInstaller` 保持只管 `COFFEEBEAN_CORE`；**不**自动加模式宏（模式由切换工具/构建脚本管）。
Hub 打开时若发现 symbols 无模式宏（既非 Beta 也非明确 Release 意图）→ 显示当前为 Release 并提示可切 Beta。

---

## 6. 模块改动清单

| 模块 | 改动 | 版本 |
|------|------|------|
| `com.coffeebean.tools` | ① CLog：Info/Warn 方法体 `#if UNITY_EDITOR || COFFEEBEAN_LOG`（Error 不变）；② 新增 `CGameBuild`；③ README 宏说明 | 0.5.0 → 0.6.0 |
| `com.coffeebean.debug` | ① `CDebug.Register/Unregister` 加 `[Conditional("COFFEEBEAN_DEV_TOOLS")]`；② `CDebugConsole` `#if COFFEEBEAN_DEV_TOOLS`；③ README/Sample 演示（Beta 宏下注册） | 0.1.1 → 0.2.0 |
| `com.coffeebean.core` | Hub（ModuleManagerWindow）加"构建模式 Beta/Release"切换区块（§5） | 0.1.41 → 0.1.42 |
| 游戏工程 | 构建 Profile/脚本（Release 清宏硬保险）+ 启动按 `CGameBuild` 初始化（§7） | — |

> 测试工具用 `[Conditional]` 无返回值约束兼容（Register/Unregister 均 void）。
> 宏组合验证：EditMode 只能验"当前 symbols"路径（编辑器态）；Release 剥离用 Release 构建产物抽检验证（文档 §8）。

---

## 7. 游戏工程接入（IdleMedievalLife 示例）

1. Hub 里切到 Beta（或构建脚本加宏）开发；日常打测试包直接 Build
2. 启动代码：
   ```csharp
   CLog.InfoEnabled = true;                    // 运行时第二道（宏之上）
   #if COFFEEBEAN_DEV_TOOLS
   CDebug.Register("goto", "跳场景", args => SceneManager.LoadScene(args[0]), 1);
   CDebug.Register("add_gold", "加金币", args => GameSave.AddGold(int.Parse(args[0])), 1);
   #endif
   ```
3. 提审/上架：Hub 切 Release（或 CI Release Profile 无宏）→ 构建 → 产物抽检
4. 验证：Release apk/aab 内无 `CDebugConsole`/`add_gold` 等字符串；运行无 Info/Warn；Error 正常

---

## 8. 测试与验证计划

- EditMode：当前（编辑器 Beta/Release 随符号）路径下 debug/tools 现有测试全绿（回归）
- debug 新增：`CDebug.Register` 编辑态可注册（宏在）；`CGameBuild.HasDevTools/HasLogging` 编辑态判定
- Hub 模式切换：EditMode 测试切 symbols → 判定函数结果翻转（`internal` 暴露给测试）；切换后提示重编译
- Release 剥离验证：Release 构建产物抽检（无工具字符串、无 Info/Warn 输出）——列入发布验收

---

## 9. 待确认

1. `CGameBuild` 放 tools（新类型，全员可引）确认？
2. debug 0.2.0 中 `CDebugConsole` 用 `#if` 剔除（Release 无类型）——业务若有"仅开发引用"需随宏包裹，OK？
3. 切换工具默认只切当前平台组 + "应用到全部组"按钮，还是直接总是切全部组？
4. 开工顺序：tools 0.6.0 → debug 0.2.0 → core 0.1.42（Hub 切换）三连发，照此进行？
