# CoffeeBean 对象池模块设计（com.coffeebean.pooling）

> 版本：v0.1（草案，待确认）
> 状态：**已实施（v0.1.0，2025）**——CPool&lt;T&gt; / CGameObjectPool / IPoolable / ReleaseDelayed 已实现并发布；测试 23 个（EditMode）

---

## 1. 定位与独立性

| 项 | 决策 |
|----|------|
| 包名 | `com.coffeebean.pooling`（程序集 `CoffeeBean.Pooling`，命名空间 `CoffeeBean.Pooling`） |
| 依赖 | **无（独立模块）**——路线图原写依赖 core，按 purchase/tools 先例改为独立 + Core 可选集成（Bridge 条件编译，注册进 ServiceRegistry） |
| 其他模块依赖 | 无 |

> 理由：对象池核心（借还 + 容量管理）是纯 C# 逻辑，不依赖任何模块；
> 与 Core 的集成（注册默认池实例）走 Bridge，安装 Core 时自动生效，与 purchase/tools 模式一致。

## 2. 核心能力

### 2.1 纯 C# 对象池 `CPool<T>`
- 泛型池（`T : class`），构造函数注入创建工厂与生命周期回调：
  - `Get()` 借出：空闲队列优先，不足时走工厂新建（超上限可配"溢出即弃"）
  - `Release(item)` 归还：回空闲队列，超上限直接丢弃（不持有）
  - `Prewarm(count)` 预热、`Clear()` 清空
- 统计：`CountInactive` / `CountActive` / `PeakCount`
- 线程安全：默认主线程使用（加锁可选）；纯逻辑，可完整单元测试

### 2.2 GameObject 池 `CGameObjectPool`（Prefab 池）
- 以 Prefab 为模板的实例池（解决 Instantiate/Destroy 高频开销）：
  - `Get(position, rotation)` 借出：激活 + 复位 transform + 触发 `IPoolable.OnSpawned`
  - `Release(instance)` 归还：失活 + 挂回池节点 + 触发 `IPoolable.OnDespawned`
  - 溢出策略：超出最大池容量的实例销毁（默认不销毁，池上限 0 = 不限制）
  - `Prewarm(count)` 预热、`Clear()` 全部回收/销毁
- 自动回收：`ReleaseDelayed(instance, seconds)`（协程计时归还，特效/弹道等"用完即回"）

### 2.3 池化生命周期回调 `IPoolable`（可选）
- `OnSpawned()` / `OnDespawned()`：MonoBehaviour 实现此接口即可在借出/归还时收到通知（零反射，`GetComponent<IPoolable>` 缓存）

### 2.4 集成
- `CPool.Default` / `CGameObjectPool.DefaultParent`（可选全局默认）
- Bridge：安装 Core 时注册 `CPool`（工厂委托由业务配置）进服务注册表

## 3. 命名与目录结构（C 前缀 + 类别分组）

```
Runtime/
├── Core/            IPool.cs（接口）、CPool.cs（纯 C# 池）
├── GameObject/      CGameObjectPool.cs、IPoolable.cs
└── Bridge/          与 Core 的可选集成（defineConstraints COFFEEBEAN_CORE）
Tests/
├── Core/            CPoolTests（借还/预热/上限/溢出/清空/统计）
└── GameObject/      CGameObjectPoolTests（EditMode：借还/复位/回调/延迟回收）
```

## 4. 约束与线程模型

- **Unity API（GameObject/Transform）必须主线程**：`CGameObjectPool` 全部方法主线程调用
- `CPool<T>` 纯逻辑：默认主线程，内部用 `ConcurrentQueue`/锁可安全跨线程（文档注明）

## 5. 测试策略

| 层 | 方式 |
|----|------|
| `CPool<T>` | 纯逻辑单测：复用工厂实例、预热数量、上限丢弃、借还一致性、统计 |
| `CGameObjectPool` | EditMode：创建/释放实例数量守恒、transform 复位、`IPoolable` 回调触发、延迟回收 |
| 边界 | null 参数、重复 Release、Get 空池时走工厂、上限为 0 不限制 |

## 6. 实施阶段

| Phase | 内容 |
|-------|------|
| 0 | 仓库骨架（package.json / asmdef / README / CHANGELOG / link.xml） |
| 1 | `CPool<T>` + `IPool` 接口 + 测试 |
| 2 | `CGameObjectPool` + `IPoolable` + 测试 |
| 3 | Bridge 集成 + **PoolingDemo 示例**（纯对象池 + Prefab 池借还演示） |
| 4 | 文档 + 全量验证 + 发布（GitHub Release + registry 同步 + 游戏 manifest） |

## 7. 已确认决策

| 决策 | 结论 |
|------|------|
| 独立性 | **独立模块**（无依赖）+ Core 可选集成（Bridge），与 purchase/tools 一致 |
| API 形态 | **双形态**：`CPool<T>`（纯 C#）+ `CGameObjectPool`（Prefab 池） |
| 溢出策略 | 空闲队列超上限即弃（不扩容持有）；`CGameObjectPool` 上限 0 = 不限制 |
| 生命周期回调 | 可选接口 `IPoolable`（OnSpawned / OnDespawned），零反射 |
| 自动回收 | `ReleaseDelayed(instance, seconds)` 协程实现 |
| 命名 | 类 `C` 前缀；接口 `I` 前缀 |
