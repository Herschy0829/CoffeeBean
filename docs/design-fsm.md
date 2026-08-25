# CoffeeBean 状态机模块设计（com.coffeebean.fsm）

> 版本：v0.1（草案，待确认）
> 状态：**已实施（v0.1.0，2025）**——CStateMachine&lt;TStateId&gt; / IState / 全局状态 / OnStateChanged 已实现并发布；测试 14 个（EditMode）

---

## 1. 定位与独立性

| 项 | 决策 |
|----|------|
| 包名 | `com.coffeebean.fsm`（程序集 `CoffeeBean.Fsm`，命名空间 `CoffeeBean.Fsm`） |
| 依赖 | **无（独立模块）**——路线图原写依赖 core，按 pooling 先例改为独立 + Core 可选集成（Bridge 条件编译） |
| 其他模块依赖 | 无 |

> 理由：状态机核心（状态注册 / 切换 / 生命周期）是纯 C# 逻辑，不依赖任何模块；
> 与 Core 的集成走 Bridge（模块标记 + 生命周期），模式与 purchase/tools/pooling 一致。

## 2. 核心能力

### 2.1 状态机 `CStateMachine<TStateId>`
- 泛型状态 ID（`TStateId : struct`）：枚举 / int 等值类型均可（string 不支持；枚举不满足 IEquatable&lt;T&gt; 泛型约束，内部统一用 EqualityComparer 比较）
- **状态注册**：`AddState(id, IState)`，状态实现 `IState` 接口（OnEnter / OnExit / OnUpdate）
- **切换**：`ChangeState(id)`：
  - 当前状态 OnExit → 目标状态 OnEnter（严格顺序）
  - 切换到**当前状态**不重入（忽略并警告）
  - 未注册的状态抛异常（尽早暴露配置错误）
- **初始状态**：`Start(id)` 首次进入（等价 ChangeState，但语义为启动）；`HasStarted` 标记
- **每帧驱动**：`Update()` 调用 当前状态 OnUpdate + 全局状态 OnUpdate
- **全局状态** `GlobalState`（可选）：任何状态下每帧执行（不随切换进出，无 OnEnter/OnExit）
- **事件**：`OnStateChanged(prevId, newId)`（切换完成回调）

### 2.2 状态实现 `IState`
```csharp
public interface IState
{
    void OnEnter();   // 进入状态（切换时）
    void OnExit();    // 退出状态（切换时；全局状态除外）
    void OnUpdate();  // 每帧（状态机 Update 驱动）
}
```
- 业务状态为普通 C# 类实现接口（可持有 owner 引用，无 Unity 依赖）
- 不提供抽象基类（接口更灵活：状态可继承业务基类）

### 2.3 辅助
- `CStateMachine<T>.CurrentStateId` / `CurrentState` / `IsInState(id)`
- `Clear()`：清空注册（重置状态机）

### 2.4 v1 不做（文档注明，后续版本）
- **Transition 表**（声明式条件转移）：v1 用显式 `ChangeState`（业务逻辑驱动切换，更直观、易调试）
- **层次状态机（HSM）** / **状态栈回退（Push/Pop）**：复杂度高，按需后续
- 依赖 events 模块的状态切换广播：自带 `OnStateChanged` 事件即可（需要事件总线时业务自行转发）

## 3. 命名与目录结构（C 前缀 + 类别分组）

```
Runtime/
├── Core/        CStateMachine.cs、IState.cs、StateMachineException.cs（可选）
└── Bridge/      与 Core 的可选集成（defineConstraints COFFEEBEAN_CORE）
Tests/
├── Core/        CStateMachineTests（切换顺序/防重入/非法状态/全局状态/事件/初始状态）
└── (示例状态类)
```

## 4. 约束与线程模型

- 核心纯 C# 逻辑：默认主线程使用（状态机持有业务状态，线程安全由调用方保证，文档注明）
- 无 Unity 依赖，可完整单元测试

## 5. 测试策略

| 项 | 方式 |
|----|------|
| 切换生命周期 | 顺序断言：旧 OnExit → 新 OnEnter；仅一次 |
| 防重入 | 同 ID 重复 ChangeState 不触发回调（忽略） |
| 非法状态 | 未注册 ID 抛异常；null 状态注册抛异常 |
| 全局状态 | 任意切换后 OnUpdate 仍被驱动；不触发 OnEnter/OnExit |
| 事件 | OnStateChanged 携带 prev/new；Start 时 prev 为 null |
| 驱动 | Update 按序驱动当前状态与全局状态 |
| 边界 | 空状态机 Start 抛异常；重复 AddState 覆盖/抛异常（决策：抛异常防误配） |

## 6. 实施阶段

| Phase | 内容 |
|-------|------|
| 0 | 仓库骨架（package.json / asmdef / README / CHANGELOG / link.xml） |
| 1 | `IState` + `CStateMachine<T>` + 测试 |
| 2 | Bridge 集成 + **FsmDemo 示例**（单位 AI：空闲/巡逻/工作/战斗 状态演示） |
| 3 | 文档 + 全量验证 + 发布（GitHub Release + registry 同步 + 游戏 manifest） |

## 7. 已确认决策

| 决策 | 结论 |
|------|------|
| 独立性 | **独立模块**（无依赖）+ Core 可选集成（Bridge） |
| 状态 ID | 泛型 `TStateId`（值类型：枚举 / int 等；string 不支持——可空事件参数需要 struct 约束） |
| 状态实现 | **接口 `IState`**（OnEnter/OnExit/OnUpdate），不强制基类 |
| 切换方式 | v1 显式 `ChangeState`（无 Transition 表，后续版本按需加） |
| 全局状态 | 支持（不随切换进出） |
| 防重入 / 非法 | 同状态忽略（警告）；未注册 / null 抛异常 |
| 事件 | 自带 `OnStateChanged(prev, new)`（不依赖 events 模块） |
| 命名 | 类 `C` 前缀；接口 `I` 前缀 |
