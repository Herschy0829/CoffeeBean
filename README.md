# CoffeeBean

模块化 Unity 框架：**一个模块 = 一个 GitHub 仓库 = 一个独立功能**。任何游戏工程通过 Unity Package Manager 的 Git 引用接入模块，由 Core 模块统一管理模块的安装 / 卸载 / 升级 / 依赖 / 版本兼容。

## 仓库结构

```
CoffeeBean/                      # 框架根仓库（本仓库）
├── .github/workflows/           # CI：checkout dev/ + clone 各模块 → 跑 EditMode 测试
├── docs/
│   ├── design.md                # 框架设计文档（先读这个；§0 说明已演进的架构）
│   └── ci.md                    # CI 说明（工作流已就位，启用只差授权 secret）
├── packages/                    # 各模块的开发 checkout（各自独立 git 仓库，不入库）
├── templates/
│   └── module/                  # 新模块脚手架（复制即用，Bridge 模式）
├── scripts/
│   └── run-editmode-tests.ps1   # 本地跑 EditMode 测试（等价于 CI）
└── dev/                         # 联调 Unity 工程（**已入库**：CI 需要一个消费工程来跑测试）
```

> `packages/` 已被 `.gitignore` 忽略：每个模块在 `packages/` 下是独立的 git 仓库，各自推送各自的 GitHub 仓库。
> CI 与本地联调都需要把模块 clone 进 `packages/`（`dev/Packages/manifest.json` 用 `file:` 引用它们）。

> **CI 状态**：模块仓库本身只是"包"、不是 Unity 工程，测试必须在消费工程（`dev/`）里跑 ——
> 因此 `dev/` 已入库，CI 放在根仓库。工作流已就位且**干净 checkout 的完整流程已在本地验证通过（461/461）**；
> 在 GitHub 上真正跑起来只差 Unity 授权 secret。详见 `docs/ci.md`。

## 模块列表

| 模块 | 功能 | Git 引用 |
|------|------|----------|
| `com.coffeebean.ad` | 广告（统一框架：激励/插屏(可选)/生命周期/可插拔后端/打点联动，依赖 tools + telemetry） | `https://github.com/Herschy0829/com.coffeebean.ad.git#v0.2.0` |
| `com.coffeebean.asset` | 资源（Addressables 封装：加载/实例化/预加载/标签/引用计数释放 + Pin 常驻 + 自动释放钩子 + 依赖分析 + 组件绑定 + 更新下载，可插拔后端，依赖 tools + addressables） | `https://github.com/Herschy0829/com.coffeebean.asset.git#v0.3.0` |
| `com.coffeebean.build` | 原生导出定制（Android Studio / Xcode 工程导出后处理：AndroidManifest/gradle/properties/libs/res/环境注入 + iOS plist/framework/BuildSettings/Capability + Google Play 150MB AAB 分包(PAD asset packs)，幂等 + dry-run，依赖 tools） | `https://github.com/Herschy0829/com.coffeebean.build.git#v0.2.0` |
| `com.coffeebean.core` | 模块管理 / 引导 / 服务注册（Window/CoffeeBean 工具中心：模块管理 + 构建模式 Beta/Release 切换，含 COFFEEBEAN_CORE 宏安装） | `https://github.com/Herschy0829/com.coffeebean.core.git#v0.1.44` |
| `com.coffeebean.debug` | 调试（游戏内控制台：日志捕获/过滤/搜索 + 作弊命令系统，Beta/Release 构建模式——Release 下作弊注册被编译移除、控制台不进包；依赖 tools） | `https://github.com/Herschy0829/com.coffeebean.debug.git#v0.2.0` |
| `com.coffeebean.di` | 依赖注入（容器：构造/字段注入、单例/瞬时/作用域、子作用域，零依赖） | `https://github.com/Herschy0829/com.coffeebean.di.git#v0.1.1` |
| `com.coffeebean.events` | 事件系统（EventBus 轻量 + EventCenter 受管） | `https://github.com/Herschy0829/com.coffeebean.events.git#v0.3.0` |
| `com.coffeebean.excel` | Excel 配置表工具链（Editor-only：多 Sheet/分章节/增量批量/加密 JSON 运行时加载/生成代码独立 asmdef + CoffeeBean 统一命名空间） | `https://github.com/Herschy0829/com.coffeebean.excel.git#v0.2.3` |
| `com.coffeebean.fsm` | 状态机（泛型 CStateMachine + 全局状态，独立无依赖） | `https://github.com/Herschy0829/com.coffeebean.fsm.git#v0.2.0` |
| `com.coffeebean.input` | 输入（命名动作抽象：键绑定/查询/事件，键盘/鼠标/触屏统一，后端可插拔，依赖 tools） | `https://github.com/Herschy0829/com.coffeebean.input.git#v0.1.2` |
| `com.coffeebean.net` | 网络（HTTP / TCP / WebSocket，帧协议 + 可插拔编解码，依赖 tools） | `https://github.com/Herschy0829/com.coffeebean.net.git#v0.2.0` |
| `com.coffeebean.pooling` | 对象池（CPool 纯 C# 泛型池 + CGameObjectPool Prefab 池，独立无依赖） | `https://github.com/Herschy0829/com.coffeebean.pooling.git#v0.2.0` |
| `com.coffeebean.purchase` | 内购（Unity IAP 5.4，Excel 配置经 excel 模块，可选服务器核销） | `https://github.com/Herschy0829/com.coffeebean.purchase.git#v0.4.0` |
| `com.coffeebean.save` | 存档（MemoryPack 序列化 + AES 加密，原子写 / 损坏回退 / 自动档节流 / 版本迁移，**内嵌 MemoryPack 二进制** + UniRx 格式化器，依赖 tools） | `https://github.com/Herschy0829/com.coffeebean.save.git#v0.3.0` |
| `com.coffeebean.telemetry` | 打点（统一事件上报：热插拔后端 + SDK 未就绪事件缓存，依赖 tools） | `https://github.com/Herschy0829/com.coffeebean.telemetry.git#v0.1.1` |
| `com.coffeebean.tools` | 工具模块（单例 / 主线程调度 / 线程池 / 构建模式门面 CGameBuild，CLog 按 Beta/Release 剥离，独立无依赖） | `https://github.com/Herschy0829/com.coffeebean.tools.git#v0.6.0` |
| `com.coffeebean.ui` | UI（UGUI 面板管理：CUIManager/CUIPanel/6 层级/栈导航/遮罩/统计/可插拔加载器 + 面板转场动画 + CBind 代码生成，依赖 tools + asset） | `https://github.com/Herschy0829/com.coffeebean.ui.git#v0.2.4` |

## 快速开始（游戏工程侧）

1. 新建 Unity 工程（Unity 6 / 6000.x）
2. 编辑 `Packages/manifest.json`，添加：

   ```json
   {
     "dependencies": {
       "com.coffeebean.core": "https://github.com/Herschy0829/com.coffeebean.core.git#v0.1.44"
     }
   }
   ```

3. 等待 UPM 解析完成后，打开 `Window > CoffeeBean`（工具中心）一键安装其他模块
4. 入口场景创建一个空物体，挂上 `CoffeeBeanBootstrap` 组件 → 框架自动引导

## 命名空间（统一 using）

**自 v0.2.0 起，所有模块的主类型统一在 `CoffeeBean` 根命名空间**——业务代码只需一个 using：

```csharp
using CoffeeBean;   // 覆盖所有模块主类型

CLog.Info("Game", "日志");                  // tools
var client = new CHttpClient();             // net
var pool = new CPool<Bullet>(() => new Bullet());   // pooling
var fsm = new CStateMachine<UnitState>();   // fsm
var bus = new EventBus();                   // events
```

- 模块内部辅助类型 / 编辑器工具 / 示例保留 `CoffeeBean.X` 子命名空间（父命名空间自动可见）
- **升级到 v0.2.0 时**：移除旧的 `using CoffeeBean.Tools;` / `using CoffeeBean.Net;` 等（类型已上移根命名空间）

## 本地多仓库联调开发

在 `packages/` 下 clone 各模块仓库，然后打开 `dev/` Unity 工程（它已通过 `file:` 路径引用本地模块）。修改模块代码立即生效，无需重新拉取。

## 跑测试

```powershell
pwsh -File scripts/run-editmode-tests.ps1                                  # 全部 EditMode
pwsh -File scripts/run-editmode-tests.ps1 -Assembly CoffeeBean.Build.Tests  # 单个模块
```

测试必须在 `dev/`（消费工程）里跑 —— 模块仓库本身只是"包"，不是 Unity 工程。
CI 见 `docs/ci.md`（工作流已就位，启用只差授权 secret）。

## 新建一个模块

复制 `templates/module/` 到 `packages/`，按 `PLACEHOLDERS.md` 替换占位符，推送自己的 GitHub 仓库，然后在根仓库的模块清单（`com.coffeebean.core/Editor/Resources/coffeebean.registry.json`）里登记。

> 模板采用 **Bridge 模式**（模块不硬依赖 Core，装了 Core 才自动接入）。`PLACEHOLDERS.md` 里有完整的
> 目录约定、两处依赖声明规则和发布检查清单 —— 新建模块前请通读一遍。

## 文档

- 框架设计：`docs/design.md`（架构、模块规范、版本约定、实施路线）
  - **§0 架构演进**：原始设计里"所有模块依赖 Core""模块间禁止横向依赖"两条已被实际架构取代，先读 §0
- 各模块设计：`docs/design-*.md`（net / save / ui / asset / excel / iap / ad / native / fsm / pooling / build-modes）
- CI：`docs/ci.md`（为什么 CI 在根仓库、干净 checkout 已验证 461/461、启用需要的 secret）

## License

[MIT](LICENSE.md)
