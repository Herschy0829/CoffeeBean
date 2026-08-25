# CoffeeBean 框架设计文档

> 版本：v0.2（设计定稿，已确认关键决策）
> 状态：待实施

---

## 1. 目标与原则

### 1.1 目标
- 模块化 Unity 框架：**一个模块 = 一个 GitHub 仓库 = 一个独立功能**
- 任何游戏工程通过 UPM **Git 引用**接入模块（`manifest.json` 里写 git URL）
- 提供 **Core 模块**统一管理其他模块的**安装 / 卸载 / 升级 / 依赖检查 / 版本兼容**
- 模块可独立发布、独立升级、按需组合

### 1.2 核心原则
| # | 原则 | 说明 |
|---|------|------|
| 1 | 一切皆 UPM 包 | 每个模块是标准 UPM 包（含 `package.json`），不依赖具体目录位置 |
| 2 | 单一职责 | 一个模块只做一件事；模块之间**禁止横向依赖** |
| 3 | Core 最小化 | Core 只负责"管理"（注册/引导/服务定位/装卸载工具），业务能力全部下沉到各模块 |
| 4 | 依赖单向 | 所有模块 → 依赖 Core（唯一无依赖的模块）；横向需求通过服务注册表解耦 |
| 5 | 语义化版本 | SemVer + git tag；默认锁定 release tag，稳定可复现 |
| 6 | 离线可用 | 官方模块目录（registry）内置一份默认值，远程不可用时降级 |

---

## 2. 总体架构

```
┌──────────────────────────────────────────────────────┐
│                 游戏工程 (Player Project)               │
│   Packages/manifest.json                              │
│     "com.coffeebean.core"   → git#v1.0.0              │
│     "com.coffeebean.events" → git#v1.0.0              │
└───────────────────────┬──────────────────────────────┘
                        │ UPM 解析（含 git 传递依赖）
┌───────────────────────▼──────────────────────────────┐
│                CoffeeBean 模块层                        │
│   Core(注册/引导) ──▶ Events ──▶ Pooling ──▶ ...      │
│   · 依赖图：Core 是根，所有模块直接/间接依赖 Core        │
│   · 模块间无横向依赖（需要时走 Core 的 ServiceRegistry）│
└──────────────────────────────────────────────────────┘
```

**模块依赖方向**（强制）：
- 每个模块只允许依赖 `com.coffeebean.core` 或其他**职责更底层**的模块
- 禁止 A↔B 循环依赖（Core 引导期做环检测，发现即报错）
- 模块间调用优先走 `CoffeeBeanContext.Services`（服务注册表），而不是直接引用对方程序集

---

## 3. 仓库布局（已确认）

### 3.1 两层仓库结构
- **框架根仓库**（本目录 `CoffeeBean`）：框架级资产——本文档、模块模板、开发工程模板、框架级 registry 汇总
- **模块仓库**（每个模块一个）：`com.coffeebean.core`、`com.coffeebean.events`、`com.coffeebean.di` …，全部挂在个人 GitHub 账号下（暂不建组织，后续可迁移）

### 3.2 根仓库 Workspace 布局
```
CoffeeBean/                          # 框架根仓库（git）
├── docs/                            # 框架级文档（本文件）
├── packages/                        # 各模块的开发 checkout（各自独立 git 仓库）
│   ├── com.coffeebean.core/         #   Core 模块仓库
│   └── com.coffeebean.events/       #   events 模块仓库
├── dev/                             # 联调开发工程（Unity 项目，.gitignore 不入库）
├── templates/
│   └── module/                      # 新模块脚手架模板（复制即用）
├── .gitignore                       # 忽略 packages/、dev/、Library/ 等
└── README.md
```
- `packages/` 下每个子目录是**独立的 git 仓库**（本地多仓库工作区），根仓库通过 `.gitignore` 忽略它们，避免嵌套仓库冲突
- 各模块仓库远程推送后，任何工程都能用 git URL 引用；本地开发用 `file:` 路径引用 `packages/` 里的 checkout

### 3.3 Git 引用方式（消费侧）
| 场景 | manifest.json 写法 |
|------|-------------------|
| 稳定（默认） | `"com.coffeebean.events": "https://github.com/Herschy0829/com.coffeebean.events.git#v1.0.0"` |
| 开发分支 | `"...git#develop"` |
| 本地开发 | `"com.coffeebean.events": "file:../packages/com.coffeebean.events"` |

---

## 4. 模块规范（每个模块仓库必须遵守）

### 4.1 命名
| 项 | 约定 | 示例 |
|----|------|------|
| UPM 包名 | `com.coffeebean.<module>` | `com.coffeebean.events` |
| GitHub 仓库名 | 与包名一致 | `<账号>/com.coffeebean.events` |
| 目录名 | 与包名一致（UPM 约定） | `com.coffeebean.events/` |
| Runtime 程序集 | `CoffeeBean.<Module>` | `CoffeeBean.Events.asmdef` |
| Editor 程序集 | `CoffeeBean.<Module>.Editor` | `CoffeeBean.Events.Editor.asmdef` |
| 框架自有类型 | **`C` 前缀**（CoffeeBean 专属，与业务/第三方类型区分） | `CSingleton<T>`、`CSingletonMono<T>`、`C` 后续命名沿用 |

### 4.2 目录结构（模板，见 `templates/module/`）
```
com.coffeebean.events/
├── package.json            # UPM 清单（必选）
├── README.md               # 必选
├── CHANGELOG.md            # 必选，发布必须更新
├── LICENSE.md              # 推荐
├── Documentation~/         # 可选（带 ~ 不会被导入工程）
├── Runtime/                # 运行时程序集
│   ├── CoffeeBean.Events.asmdef
│   └── ...
├── Editor/                 # 编辑器程序集（可选）
├── Tests/                  # 测试（推荐，Editor/PlayMode 各一套）
└── Samples~/               # 示例（必选，随模块发布；模块更新时同步维护）
```

> 约定：**每个模块必须有 `Samples~/` 示例**（package.json 的 `samples` 字段登记，Package Manager 可一键导入）；
> 模块功能更新时，示例必须同步更新，没有示例的模块需要补上（见 `templates/module/Samples~/` 骨架）。

### 4.3 package.json 示例（目标 Unity 6）
```json
{
  "name": "com.coffeebean.events",
  "version": "1.0.0",
  "displayName": "CoffeeBean Events",
  "description": "Type-safe event bus for CoffeeBean.",
  "unity": "6000.0",
  "dependencies": {
    "com.coffeebean.core": "1.0.0"
  }
}
```
> UPM 会自动解析 git 包的**传递依赖**，所以模块只需声明直接依赖。

### 4.4 模块标识（运行期可发现）
每个模块 Runtime 程序集顶部声明（Attribute 由 Core 提供）：

```csharp
[assembly: CoffeeBeanModule(
    "com.coffeebean.events",
    "1.0.0",
    DisplayName   = "Events",
    Description   = "Type-safe event bus.",
    Dependencies  = new[] { "com.coffeebean.core" }   // 与 package.json 保持一致
)]
```

Core 启动时扫描带 `[CoffeeBeanModule]` 的程序集 → 得到**已安装模块清单**。
> 注意：构建时 Unity 链接器可能裁剪未引用的 Attribute，Core 提供 `link.xml` 保留规则，并建议模块侧也加一份。

### 4.5 生命周期接口（可选实现）
```csharp
public interface ICoffeeBeanModule
{
    void OnLoad(CoffeeBeanContext ctx);   // 依赖全部就绪后调用；在此注册服务
    void OnStart();                       // 所有模块 OnLoad 完成后
    void OnShutdown();                    // 退出时按依赖反序调用
}
```
纯库模块（如 pooling）可不实现接口，只注册服务。

---

## 5. 版本约定

- SemVer：`MAJOR.MINOR.PATCH`，git tag 命名 `v1.0.0`
- **MAJOR 不一致 = 不兼容**（Module Manager 阻止静默升级，需显式确认）
- Core 的 MAJOR 升级 = 框架整体 breaking（所有模块需跟进）
- 每个模块声明所需 Core 最低版本，运行时校验，不满足则 fail-fast 并给出明确日志
- CHANGELOG 强制维护

---

## 6. Core 模块设计（仓库 `com.coffeebean.core`）

### 6.1 职责划分
| 组件 | 职责 |
|------|------|
| `CoffeeBeanModuleAttribute` | 模块标识（Core 定义，各模块引用） |
| `CoffeeBeanRegistry` | 发现 + 查询已安装模块（含依赖图） |
| `CoffeeBeanBootstrapper` | 依赖拓扑排序、环检测、生命周期驱动 |
| `CoffeeBeanContext` / `ServiceRegistry` | 模块间服务定位（解耦横向依赖） |
| `CoffeeBeanConfig` | 运行期模块启用/禁用开关（ScriptableObject） |
| `ModuleManager`（Editor） | 安装/卸载/升级/检查，编辑器窗口 + API |
| `RegistrySource` | 官方模块目录（内置 json + 可选远程覆盖） |

### 6.2 安装 / 卸载机制（重点）

> UPM 包是**编译期**概念：安装/卸载 = 修改 `Packages/manifest.json` 并让 UPM 重新解析编译。
> 运行期只有**启用/禁用**（包还在，只是不 Load）。

**安装 Install**
```
ModuleManager.Install("com.coffeebean.events", "v1.0.0")
  → 检查依赖是否已满足（缺依赖则提示先装或自动装）
  → 版本兼容校验（对已装模块无冲突）
  → UnityEditor.PackageManager.Client.Add("https://...git#v1.0.0")
  → 等待解析完成 → 重新编译 → 刷新模块清单 → 日志
```
- 备选实现：直接编辑 manifest.json（Client.Add 不可用 / 批量场景 / 无人值守 CI）

**卸载 Uninstall**
```
ModuleManager.Uninstall("com.coffeebean.events")
  → 安全检查：查依赖图，若有其他已安装模块依赖它 → 拒绝并列出依赖方
  → Client.Remove("com.coffeebean.events")
  → 重编译 → 刷新清单
```

**运行期启用/禁用 Enable/Disable（不删包）**
- `CoffeeBeanConfig` 资产（自动生成于 `Assets/CoffeeBean/Config.asset`）控制启动时哪些模块 Load
- 用于性能裁剪、A/B、模块灰度

**Module Manager 窗口**（`Window > CoffeeBean > Module Manager`）
| 分区 | 内容 |
|------|------|
| Installed | 已装模块：ID / 版本 / git URL / 依赖 / 状态 / 健康度 |
| Available | 官方目录（来自 registry）：一键安装 / 升级到最新 tag |
| Graph | 依赖图视图、环/冲突/缺依赖警告 |
| Log | 操作历史与错误 |

### 6.3 模块目录 RegistrySource
```json
// com.coffeebean.core/Editor/Resources/coffeebean.registry.json（内置默认）
{
  "version": 1,
  "modules": [
    { "id": "com.coffeebean.events", "repo": "https://github.com/Herschy0829/com.coffeebean.events.git", "latest": "v1.0.0" }
  ]
}
```
- 内置默认保证离线可用；`ProjectSettings/CoffeeBean` 可配置远程 URL（raw.githubusercontent）覆盖
- 非官方模块：Module Manager 提供"Add custom git URL"入口，照常纳入依赖检查

### 6.4 引导流程（运行期）
```
入口场景放置 CoffeeBeanBootstrap（组件或静态入口；组件自带 DontDestroyOnLoad 跨场景常驻 + 单例保护，
Loading → Main 场景切换不会销毁框架，上下文全程存活）
  → Bootstrapper.Load()
  → 扫描 [CoffeeBeanModule] 程序集 → 按 CoffeeBeanConfig 过滤 → 构建模块图
  → 拓扑排序 + 环检测（依赖在前）
  → 逐模块 OnLoad(ctx)（注册服务到 ServiceRegistry）
  → 全部完成后统一 OnStart()
  → 游戏逻辑
  → 退出按依赖反序 OnShutdown()
```

---

## 7. 模块路线图

**首批（本期）**
| 包 | 功能 | 依赖 | 状态 |
|----|------|------|------|
| `com.coffeebean.core` | 模块管理 / 引导 / 服务注册 | 无 | 本期实施 |
| `com.coffeebean.events` | 事件系统（EventBus 轻量 + EventCenter 受管） | core | 本期实施 |
| `com.coffeebean.purchase` | 内购（Unity IAP 5.4，Excel 配置，可选服务器核销） | 无（独立） | 本期实施 |
| `com.coffeebean.tools` | **工具模块**：单例 / 主线程调度 / 线程池 | 无（独立） | 本期实施 |

> **工具模块规则**：`com.coffeebean.tools` 不依赖任何模块，供其他模块依赖；
> 其他模块"出于纯净度不适合放在模块内"的通用/零碎工具，拆分到工具模块后依赖它。

**后续规划（按需逐个建）**
| 包 | 功能 | 依赖 |
|----|------|------|
| `com.coffeebean.di` | 依赖注入容器 | core |
| `com.coffeebean.pooling` | 对象池 | core |
| `com.coffeebean.fsm` | 状态机 | core |
| `com.coffeebean.input` | 输入抽象 | core |
| `com.coffeebean.save` | 存档 / 序列化 | core |
| `com.coffeebean.ui` | UI 框架（MVVM + 面板管理） | core, di, events |
| `com.coffeebean.debug` | 运行期控制台 / 作弊工具 | core |

> 非官方模块遵循同样规范即可接入生态，无需审批。

---

## 8. 工程消费方式（游戏工程侧）

1. 新建 Unity 工程（**Unity 6 / 6000.x**）
2. `manifest.json` 添加：`"com.coffeebean.core": "https://github.com/Herschy0829/com.coffeebean.core.git#v1.0.0"`
3. 其余模块：手动添加 git URL，或打开 `Module Manager` 一键安装
4. 入口场景放 `CoffeeBeanBootstrap`（组件跨场景常驻）→ 框架启动
5. 多仓库联调开发：用 `file:` 本地路径引用 `packages/` 里的 checkout

---

## 9. 多仓库开发工作流

- **开发**：在根仓库 `packages/` 下 clone 各模块仓库，`dev/` Unity 工程用 `file:` 引用本地模块
- **包测试**：包在项目 `Packages` 目录外开发时，必须在**项目 manifest** 的 `testables` 里列出要启用测试的包（仅写包内 package.json 的 `testables` 无效）；测试 asmdef 用官方格式 `optionalUnityReferences: ["TestAssemblies"]`
- **CI**：每个模块仓库配 Unity Test Runner（EditMode + PlayMode），`on tag push` 触发
- **发布**：打 tag = 发布；`latest` 从最新 tag 读取；CHANGELOG 同步；**每次发布必须在 GitHub 对应仓库创建 Release 并写更新说明**（正文取自 CHANGELOG 当版本条目，tag 对应 `vX.Y.Z`）
- **依赖升级**：模块升级 MAJOR 时，Module Manager 在消费工程里提示所有依赖方

---

## 10. 实施步骤

| Phase | 内容 | 产出 |
|-------|------|------|
| 0 | 初始化框架根仓库（本目录） | docs、`.gitignore`、README、`templates/module/` 脚手架 |
| 1 | 建 `com.coffeebean.core` 模块仓库（`packages/` 下） | package.json、目录骨架、Attribute/Registry 核心代码骨架 |
| 2 | 实现 Core 核心逻辑 | Attribute / Registry / Bootstrapper / ServiceRegistry + 单元测试 |
| 3 | 实现编辑器管理能力 | Module Manager 窗口、Install/Uninstall API、RegistrySource |
| 4 | 建 `com.coffeebean.events` 验证模块 | 跨仓库 git 引用、传递依赖、引导顺序全流程验证 |
| 5 | 工程化 | 模板仓库完善、CI、发布流程、消费方示例文档 |
| 6 | 路线图扩展 | 按第 7 节逐个建模块 |

---

## 11. 已确认决策

| 决策 | 结论 |
|------|------|
| 目标 Unity 版本 | **Unity 6 (6000.x)** |
| 仓库布局 | **框架根仓库（本目录）+ 独立 Core 模块仓库** |
| 首期范围 | **Core + events 一个验证模块** |
| GitHub 账号 | **个人账号**（暂不建组织，URL 以 `Herschy0829` 占位） |
| 仓库可见性 | **后续新建的模块仓库默认公开（public）**；现有 4 个仓库（根/Core/events/purchase）保持私有，需转公开时单独处理 |
