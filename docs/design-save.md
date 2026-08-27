# CoffeeBean 存档模块设计（com.coffeebean.save）

> 版本：v0.1
> 状态：已实施（com.coffeebean.save v0.1.0，2026-08-27 发布）

---

## 1. 背景：Idle 项目序列化现状与痛点

调研 `IdleMedievalLife` 的存档与序列化实现：

| 项 | Idle 现状 | 痛点 |
|----|----------|------|
| 主存档格式 | **MemoryPack 1.21.4**（`[MemoryPackable]` + `GenerateType.VersionTolerant`，本地 file: 引用） | 高效二进制 ✓；但存档**未加密**、**无原子写**（崩溃损坏） |
| 写盘 | `MemoryPackSerialize` + 后台线程；`DeserializeFileWithRetry` 读档 | 静态字段竞态；无备份回退 |
| 旧存档 | `BinarySerializ`（BinaryFormatter） | **已废弃 API**（不安全/IL2CPP 差），被 MemoryPack 替代，可删 |
| JSON 场景 | **LitJson**（AssetMgr 清单 / 网络 / 语言表） | 第三方依赖；网络 JSON 归 net 模块，清单归资产层，不并入 save |
| 存档调度 | 定时（60s/120s）+ 失焦/退出 + 关键操作（`PlayerDataMgr`） | 合理，save 模块对齐并加节流 |
| 加密 | `EncryptHelp`（AES/XOR/MD5 工具齐全） | **主存档未加密**（仅配置表加密） |

> save 模块对齐 Idle 的 MemoryPack 方案与自动存档调度，补齐加密 / 原子写 / 备份回退 / 版本迁移 / 竞态修复。

## 2. 定位与独立性

| 项 | 决策 |
|----|------|
| 包名 | `com.coffeebean.save`（程序集 `CoffeeBean.Save`，命名空间 `CoffeeBean`——统一根命名空间） |
| 依赖 | **`com.coffeebean.tools`**（CJson 兜底序列化 / CLog 日志）+ **`com.cysharp.memorypack`**（MemoryPack，默认序列化后端） |
| MemoryPack 集成方式 | **声明包名依赖（版本范围），来源由消费工程决定**——项目已本地化（file: 引用 SDK 副本），不内嵌源码/DLL（MemoryPack 需 Roslyn 源码生成器，内嵌复杂且版本锁定）；消费工程可用 git 或 file: 提供 |
| Core 集成 | 可选（Bridge 注册 `CSaveSystem`） |

## 3. 核心能力

### 3.1 序列化后端（可插拔 `ISaveSerializer`）
- **`CMemoryPackSerializer`（默认）**：MemoryPack 二进制——高效、对齐项目现状；数据类沿用 `[MemoryPackable]` / `GenerateType.VersionTolerant`
- **`CJsonSerializer`（兜底）**：CJson（tools）——不需要 MemoryPack 的场景（简单存档 / 调试可读）
- 归纳项目自定义序列化：`BinarySerializ`（废弃，不并入）、`MemoryPackSerialize`（并入 `CSaveSystem`）、LitJson 的 JSON 场景（归 net/资产层，不并入 save）

### 3.2 加密 `CSaveEncrypt`（默认开启）
- **AES（AES-128/256，PKCS7）**：key 项目配置；IV 随机前置文件头（每次写盘不同 IV）
- 可选 XOR 混淆外层；安全边界同 excel：**混淆级**，真安全需服务器校验
- 项目现状：主存档未加密 → 补齐

### 3.3 存储 `CSaveSystem`（门面，含优化）
- 文件槽位：`persistentDataPath/{slot}.sav`；多槽位（主档 / 自动档 / 备份档）
- **原子写**（优化）：写 `{slot}.tmp` → 校验 → 重命名；崩溃不损坏旧档
- **损坏回退**（优化）：主档损坏自动读备份档（对齐 `DeserializeFileWithRetry` 并加强）
- **异步写 + 防竞态**（优化）：后台线程写盘（Task），串行队列避免多档互踩（修复 BinarySerializ 静态字段问题）
- **自动存档 + 节流**（优化）：`StartAutoSave(interval)` 定时 + 失焦/退出自动存 + 手动 Save；距上次自动存不足最短间隔跳过
- **版本迁移**：文件头 `version` + MemoryPack `VersionTolerant` + `OnMigrate` 钩子

### 3.4 API 形态

```csharp
using CoffeeBean;

var save = new CSaveSystem(new CSaveOptions
{
    Slot = "main",
    EncryptionKey = "project-key-32bytes",   // 默认开启 AES
});

save.SaveData(playerData);                          // 入队异步写盘（原子写 + 加密 + 串行）
PlayerData loaded = save.LoadData<PlayerData>();    // 读回（损坏回退 + 迁移 + 重试）
save.SetMigrator(version => { /* 旧档迁移 */ });
save.StartAutoSave(120f);                           // 定时自动存档（对齐 Idle 调度）
```

## 4. 目录结构（C 前缀 + 类别分组）

```
Runtime/
├── Core/        CSaveSystem.cs、CSaveOptions.cs、CSaveEncrypt.cs、ISaveSerializer.cs
├── Serializers/ CMemoryPackSerializer.cs、CJsonSerializer.cs
└── Bridge/      与 Core 的可选集成
Tests/
├── Core/        CSaveSystemTests（存取往返/加密/原子写/损坏回退/版本迁移/自动存档节流）
└── Serializers/ MemoryPack 后端（Dictionary/嵌套/VersionTolerant）、CJson 后端
Samples~/
└── SaveDemo/    SaveDemo（存档/读档/加密/版本迁移演示）
```

## 5. 测试策略

| 项 | 方式 |
|----|------|
| 存取往返 | 临时目录文件：Save → Load 还原（含 Dictionary / 嵌套类 / null） |
| 加密 | 密文文件不含明文；解密还原；无 key 读失败 |
| 原子写 | 写入中断（模拟 tmp 残留）不损坏旧档 |
| 损坏回退 | 主档损坏 → 自动读备份档 |
| 版本迁移 | 文件头 version=1 旧档 → 迁移钩子 → 新结构 |
| 自动存档节流 | 距上次自动存不足间隔跳过 |
| 容错 | 文件缺失 / 损坏 / 空数据 → 返回默认并告警 |

## 6. 实施阶段

| Phase | 内容 |
|-------|------|
| 0 | 仓库骨架（package.json 依赖 Newtonsoft / asmdef / README / CHANGELOG） |
| 1 | `ISaveSerializer` + `CNewtonsoftSerializer` / `CJsonSerializer` + 测试 |
| 2 | `CSaveEncrypt`（AES + XOR）+ `CSaveOptions` + 测试 |
| 3 | `CSaveSystem`（存取 / 原子写 / 备份回退 / 自动存档 / 版本迁移）+ 测试 |
| 4 | Bridge 集成 + SaveDemo 示例 |
| 5 | 全量验证 + 发布（GitHub 仓库 + registry + 游戏 manifest） |

## 7. 已确认决策

| 决策 | 结论 |
|------|------|
| 存档格式 | **MemoryPack 二进制**（默认，对齐项目现状；高效 + VersionTolerant 版本容错） |
| 序列化后端 | `ISaveSerializer` 可插拔：`CMemoryPackSerializer`（默认）+ `CJsonSerializer`（兜底，tools CJson） |
| MemoryPack 集成 | **声明包名依赖，来源消费工程定**（项目已 file: 本地化；不内嵌源码/生成器） |
| 加密 | **AES + 随机 IV + 可选 XOR**（默认开启；主存档当前未加密 → 补齐） |
| 存储 | `persistentDataPath` 文件槽位 + **原子写** + **损坏自动回退备份** |
| 写盘 | 后台线程异步 + **串行队列防竞态**（修复 BinarySerializ 静态字段互踩） |
| 自动存档 | 定时 + 失焦/退出 + 手动，**节流**（对齐 Idle 调度并优化） |
| 版本迁移 | 文件头 version + MemoryPack VersionTolerant + `OnMigrate` 钩子 |
| 归纳替换 | BinarySerializ（废弃不并入）/ MemoryPackSerialize（并入 CSaveSystem）/ LitJson JSON 场景（归 net/资产层） |
| 命名空间 | `CoffeeBean`（统一根命名空间） |
