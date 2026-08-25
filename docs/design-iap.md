# CoffeeBean 支付模块设计（com.coffeebean.purchase）

> 版本：v0.2（设计定稿，已确认决策）
> 依赖：Unity IAP **5.4.x**（com.unity.purchasing）
> 状态：待实施

---

## 1. 定位与独立性（核心约束）

### 1.1 双模式运行
| 模式 | 条件 | 行为 |
|------|------|------|
| **独立模式** | 工程未安装 Core | 模块完全独立工作，**不引用任何 CoffeeBean 模块**，package.json 只依赖 `com.unity.purchasing` |
| **集成模式** | 工程安装了 Core | 自动注册为 CoffeeBean 模块，`IapService` 注册进 Core 的服务注册表，其他模块可通过 `context.Services.Get<IapService>()` 使用；由 Core 的 Module Manager 安装/卸载 |

### 1.2 实现机制：可选依赖桥接（versionDefines）
```
CoffeeBean.Purchase.asmdef
  versionDefines: [ { "name": "com.coffeebean.core", "expression": "", "define": "COFFEEBEAN_CORE" } ]
```
- 运行时程序集**不引用** Core 程序集 → 没有 Core 也能编译
- 只有 `Runtime/Bridge.cs` 用 `#if COFFEEBEAN_CORE` 包裹：
  - `[assembly: CoffeeBeanModule("com.coffeebean.purchase", ...)]` 模块标识
  - `IapModule : ICoffeeBeanModule` —— OnLoad 时把 `IapService` 注册进 Core 服务注册表
- Core 存在 → 宏生效 → 模块被发现并集成；Core 不存在 → 桥接代码不编译，纯独立运行

> 注意：`versionDefines` 对 git/file 方式安装的包同样生效（按 package.json 的 version 匹配）。

---

## 2. 包结构

```
com.coffeebean.purchase/
├── package.json                  # deps: { "com.unity.purchasing": "5.4.0" }（无 Core 依赖！）
├── CHANGELOG.md / README.md / LICENSE.md
├── link.xml                      # 保留 IAP 相关程序集
├── Runtime/
│   ├── CoffeeBean.Purchase.asmdef     # versionDefines → COFFEEBEAN_CORE
│   ├── IapService.cs             # ★ 对外统一门面（模块的公共 API）
│   ├── IapProduct.cs             # 运行时商品数据（内部ID + 平台ID + 商店下发缓存）
│   ├── IapStoreAdapter.cs        # ★ Unity IAP 5.4 API 适配层（隔离层，唯一的 IAP 引用点）
│   ├── PurchaseFlow.cs           # 购买状态机（进行中 / 防重入 / 超时）
│   ├── ServerVerifier.cs         # IPurchaseVerifier 接口 + 全局/逐商品开关 + 重试策略
│   ├── RestoreFlow.cs            # 恢复购买流程
│   ├── IapConfig.cs              # 配置数据模型（Excel 生成产物）
│   ├── IapLog.cs                 # 可开关日志
│   └── Bridge.cs                 # #if COFFEEBEAN_CORE：模块标记 + 生命周期注册
├── Editor/
│   ├── CoffeeBean.Purchase.Editor.asmdef
│   ├── IapConfigWindow.cs        # Window > CoffeeBean > IAP：选Excel / 重新生成 / 查看结果
│   ├── ExcelImporter.cs          # Excel 解析 + 校验（NPOI）
│   ├── IapBuildHook.cs           # IPreprocessBuildWithReport：打包前强制重解析
│   └── Resources/                # （可选）默认配置模板
├── Tests/                        # EditMode 测试（配置校验 / 状态机 / 缓存查询）
└── Samples~/                     # 使用示例（可选）
```

**分层原则**：`IapStoreAdapter` 是唯一直接接触 Unity IAP API 的类，其余代码只依赖适配层暴露的接口 —— Unity IAP 后续大版本升级只改这一个文件。

---

## 3. Excel 配置规范

### 3.1 字段清单（列名 = 字段名 + 类型后缀）

| 列名 | 类型 | C# 字段 | 必填 | 校验规则 |
|------|------|---------|------|----------|
| `Id_s` | string | InternalId（内部商品ID，服务端对账/补发用） | ✅ | 非空、全局唯一 |
| `GoogleProductId_s` | string | GoogleProductId | ✅ | 非空、全局唯一 |
| `AppleProductId_s` | string | AppleProductId | ✅ | 非空、全局唯一 |
| `ConsumeType_i` | int | ConsumeType | ✅ | 仅 0/1（**v1 暂不支持订阅**）：0=Consumable，1=NonConsumable；填 2 → 校验报错"订阅暂不支持" |
| `Title_s` | string | Title（商店未下发时的兜底显示名） | | |
| `Description_s` | string | Description（兜底描述） | | |
| `Price_f` | float | PriceAnchor（价格锚点，仅展示/校验用；**实际价格以商店下发为准**） | | ≥ 0 |
| `Currency_s` | string | CurrencyOverride（货币代码覆盖，默认取商店下发） | | 3 位大写字母 |
| `Enabled_i` | int | Enabled（上架开关） | | 仅 0/1，默认 1 |
| `Group_s` | string | Group（商品分组/礼包标识，透传） | | |
| `SortOrder_i` | int | SortOrder（排序） | | |
| `Verify_i` | int | ServerVerifyOverride（该商品是否服务器二次确认） | | 仅 -1/0/1：-1=跟随全局开关，0=否，1=是 |
| `Extra_s` | string | Extra（扩展透传，JSON 字符串） | | 可 JSON 解析（警告级） |

> 类型后缀约定沿用你的规范：`_s`=string、`_i`=int、`_f`=float。

### 3.2 校验与弹窗
- 解析失败（文件损坏/格式错误）→ `EditorUtility.DisplayDialog` 直接弹窗
- 校验失败（缺必填、枚举越界、ID 重复等）→ 弹窗**汇总列出全部错误**（行号 + 列名 + 原因），并给出"已跳过 N 行"；校验未通过不允许生成配置 / 不允许打包
- 全部通过 → 弹窗提示"解析成功：N 行，生成配置 → 路径"

### 3.3 生成产物
- `IapConfig` **ScriptableObject**（`.asset`，运行时主数据源，含全局设置：服务器核销开关、验证超时、重试次数）
- **JSON** 副本（便于 CI / 服务器 / 版本对比）
- 两版内容一致，SO 为运行时读取，JSON 为旁证与外部工具用

---

## 4. 运行时功能

### 4.1 初始化与商品下发缓存（需求 a）
```
IapService.InitializeAsync()
  → 从 IapConfig 构建商品定义（含 Google/Apple 双平台 ID 映射）
  → IapStoreAdapter 初始化（Unity IAP 5.4）
  → 等待商品下发完成（超时 + 失败重试，退避策略）
  → 缓存商店下发数据：localizedPrice / price / currencyCode / title / description / type / receipt 等
```
- 查询 API（**通过对应平台的 ID 获取商品数据**）：
  - `TryGetByInternalId(string)` / `TryGetByGoogleId(string)` / `TryGetByAppleId(string)`
  - 返回 `IapProduct`：包含 `LocalizedPriceString`、`DecimalPrice`、`CurrencyCode`、`Description`、`Title` 等
- 回调：`OnInitialized` / `OnInitFailed(reason)` / `OnProductsUpdated`

### 4.2 购买流程（需求 b）

```
Purchase(internalId)
  → 校验：已初始化？商品存在？未在购买中？        ← 购买中保护
  → 置为"购买中"（防重复点击/并发）→ 超时保护
  → IapStoreAdapter.PurchaseAsync
  → 成功：
      ├─ 服务器核销关闭（或该商品 Verify_i=0）
      │     → 立即核销发货 → 回调 onPurchaseProcessed → 完成
      └─ 服务器核销开启（Verify_i=1 或全局开且未覆盖）
            → 保持 Pending（不确认）
            → 收据 + 商品ID + 交易ID 发给 IPurchaseVerifier
            → 服务器确认 → 发货 + 确认交易（Confirm）→ 完成
            → 服务器拒绝/超时(可配) → 保持 Pending，等待重试
  → 失败：回调 onPurchaseFailed(reason)（UserCancelled / NetworkError / StoreError 等分类）
```

**"补发"与防丢（关键机制）**：
- 未确认的 Pending 购买，Unity IAP v5 会在**下次启动时重新回调** → 自动重走"发货 + 确认" → 崩溃/断网不丢单
- 去重：记录已处理交易 ID（内存集合 + 可选持久化 journal），`ProcessPurchase` 重入时跳过已发货的
- 消费型商品在服务器模式下**必须 Pending 后确认**（v4 文档明确警告，v5 同理），防止卸载/重装丢单

### 4.3 恢复购买（需求 c）
```
RestorePurchases()
  → 适配层按平台调用：Apple RestoreTransactions / Google Restore（非消耗品/订阅）
  → 回调 onRestoreFinished(restoredProducts) → 业务层补发权益
  → 失败回调 onRestoreFailed(reason)
```

### 4.4 服务器二次验证（可选功能，独立可用）
- 接口：`IPurchaseVerifier { Task<VerificationResult> VerifyAsync(PurchasePayload payload) }`
- 全局开关（IapConfig）+ 逐商品覆盖（Excel `Verify_i`）
- 未设置 Verifier / 全局关闭 → 自动走"无服务器直接完成"路径（独立模式开箱即用）
- 超时 + 重试次数可配；服务器不可达时保持 Pending，不丢单

### 4.5 补充功能（我建议补的）
| 功能 | 说明 |
|------|------|
| 购买状态机 | 进行中集合 + 冷却，防重复点击；超时兜底 |
| 订阅支持（v1 不做） | 字段/枚举预留 ConsumeType=2，v1 校验拦截并提示"暂不支持订阅"；后续版本再启用 |
| 编辑器假商店 | 用 Unity IAP 的 fake store / 自研模拟器，无真机可测全流程 |
| 错误分类 | 初始化失败/商品不可用/购买失败分原因回调，便于业务层区分处理 |
| 可开关日志 | `IapLog`，静默模式 |
| 主线程保证 | 所有回调派发到主线程 |
| 价格展示辅助 | 直接拿 `LocalizedPriceString` 给 UI |
| 崩溃恢复去重 | 见 4.2 补发机制 |

---

## 5. 编辑器工具与打包监听（需求 1）

```
Window > CoffeeBean > IAP
  ├─ [选择 Excel 表]   → 路径存 EditorPrefs + IapConfig 引用；弹窗校验
  ├─ [重新生成配置]    → 重新解析当前选中的 Excel → 生成 .asset + .json
  ├─ [查看生成结果]    → 展示解析出的商品列表（只读表格）
  └─ 全局设置          → 服务器核销开关 / 验证超时 / 重试次数 / 打包前强制重解析开关
```
- **打包监听**：`IPreprocessBuildWithReport` —— 打包前若配置了 Excel 路径且开启"打包前强制重解析"（默认开），自动重新解析生成最新配置；失败则弹窗并**中止打包**（或按设置降级用上次配置 + 警告）
- 用户可以随时手动重新选择 Excel 或重新生成，互不冲突（以最近一次操作为准）

---

## 6. 与 Core 的集成 / 卸载

- **安装/卸载**：走 Core 的 Module Manager（UPM git 引用，`https://github.com/Herschy0829/com.coffeebean.purchase.git#v0.1.0`），在 `coffeebean.registry.json` 登记
- **卸载安全**：Module Manager 卸载前检查依赖方（此模块无其他 CoffeeBean 模块依赖它，通常可直接卸）
- **卸载后**：工程内残留的 `IapService` 引用需业务侧清理（模块卸载 = 移除包 + 重新编译，UPM 标准行为）

---

## 7. 已确认决策

| 决策 | 结论 |
|------|------|
| Excel 解析库 | **NPOI**（Apache-2.0，Editor-only，随包分发） |
| 订阅支持（v1） | **暂不做订阅**（ConsumeType=2 校验拦截，枚举预留） |
| 配置产物 | **ScriptableObject + JSON 双份** |
| Unity Gaming Services | **不接入**；服务器核销走自定义 `IPurchaseVerifier` |
| 包名/仓库名 | **`com.coffeebean.purchase`**（程序集 `CoffeeBean.Purchase`，命名空间 `CoffeeBean.Purchase`；类名保留 Iap* 前缀，如 `IapService`） |

---

## 8. 实施步骤

| Phase | 内容 | 产出 |
|-------|------|------|
| 0 | 仓库骨架 + 安装 com.unity.purchasing 5.4 | package.json、asmdef（含 versionDefines）、目录 |
| 1 | 配置体系 | IapConfig 模型 + ExcelImporter（解析+校验+弹窗）+ 生成产物 |
| 2 | 编辑器工具 | IapConfigWindow + 打包监听 IPreprocessBuildWithReport |
| 3 | 运行时核心 | IapStoreAdapter（隔离层）+ 初始化/缓存/查询 |
| 4 | 购买与核销 | PurchaseFlow + ServerVerifier（可选二次确认）+ 补发去重 |
| 5 | 恢复购买 | RestoreFlow |
| 6 | Core 桥接 | Bridge.cs（#if COFFEEBEAN_CORE 标记 + 生命周期注册） |
| 7 | 测试与验证 | EditMode 测试 + dev 工程编译验证 + 假商店流程验证 |
