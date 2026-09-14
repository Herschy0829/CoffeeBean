# CI（持续集成）

> 状态：**脚手架已就绪，但尚未启用** —— 启用前需要你补两件我无法代办的事，见下面「启用前提」。

## 1. 为什么还不能直接跑

设计文档 `design.md` §9 规划的是"每个模块仓库配 Unity Test Runner，`on tag push` 触发"。但按当前仓库布局，**没有一个仓库能独立跑测试**：

| 位置 | 是否是 Unity 工程 | 能否跑测试 |
|---|---|---|
| 框架根仓库（本仓库） | ❌ 只有 `docs/` `templates/` `scripts/` | ❌ |
| `packages/<模块>` | ❌ 只是 UPM 包（`package.json` + `Runtime/`…） | ❌ |
| `dev/`（联调工程） | ✅ 是 | ✅ **但它被 `.gitignore` 忽略、未入库** |

也就是说：**测试必须在一个"消费工程"里跑**（该工程的 `Packages/manifest.json` 要引用各模块，并在 `testables` 里登记才能启用其测试程序集）。目前这个工程只存在于本地 `dev/`。

## 2. 启用前提（需要你决定/提供）

### (a) `dev/` 的处置

三选一：

| 方案 | 说明 | 代价 |
|---|---|---|
| **把 `dev/` 纳入版本控制**（推荐） | CI 直接用根仓库的 `dev/`，模块按 tag 拉取到 `packages/`；与本地开发完全同构 | 要收编工程文件；`Library/` 等仍需忽略 |
| 新建精简 `ci/TestProject` | 只放 `ProjectSettings/` + `Packages/manifest.json` + 测试所需 Assets | 要重新搭一遍；Addressables 相关测试需要相应的配置资产 |
| 每个模块仓库各带一个 `TestProject~` | 模块自包含、互相不干扰 | 17 份重复工程，维护成本高 |

### (b) Unity 授权 secret

每个要跑 CI 的仓库需配：

| Secret | 必需 | 说明 |
|---|---|---|
| `UNITY_LICENSE` | ✅ | Unity 授权文件内容（`.ulf` 的 XML） |
| `UNITY_EMAIL` | 可选 | 用账号密码激活时需要 |
| `UNITY_PASSWORD` | 可选 | 同上 |

> 工作流已做**优雅跳过**：没配 `UNITY_LICENSE` 时不会报错，只打一条 notice。

### (c) 一个依赖来源问题

`com.coffeebean.save` 依赖 `com.cysharp.memorypack`，目前是**vendored 在 `dev/Packages/` 下**（也被 gitignore）。
CI 里没有这个包就编译不过 save 及其测试。需要决定：改用 git URL 引用上游、还是把 vendored 副本入库。

### (d) 其它

- GitHub Actions 分钟数：Unity 镜像很重，私有仓库按分钟计费；`actions/cache` 缓存 `Library/` 可显著降低成本（工作流已配）。
- 模块仓库大多开了"禁止直接推送、必须走 PR"的分支保护 —— CI 触发策略（tag / PR / push）需要与此一致。

## 3. 已就绪的东西

| 文件 | 用途 |
|---|---|
| `scripts/run-editmode-tests.ps1` | **本地**批处理跑 EditMode 测试，等价于 CI 要做的事。已实测可用 |
| `templates/ci/unity-tests.yml` | 模块仓库用的 GitHub Actions 工作流模板（game-ci + 缓存 + 授权跳过 + 产物上传）。把 `<TEST_PROJECT>` 换成实际工程路径后即可使用 |

### 本地跑测试

```powershell
# 全部 EditMode 测试（当前 dev 工程为 461 个）
pwsh -File scripts/run-editmode-tests.ps1

# 只跑某个模块
pwsh -File scripts/run-editmode-tests.ps1 -Assembly CoffeeBean.Build.Tests
```

> 脚本里之所以用 `Start-Process` + `Wait-Process` 而不是 `& Unity.exe`：
> **Unity.exe 是 GUI 子系统程序**，用 `&` 调用会立即返回，既拿不到退出码也等不到结果文件。

## 4. 建议的启用顺序

1. 定 (a) 方案 → 把测试工程纳入某个仓库
2. 定 (c) MemoryPack 来源
3. 在目标仓库配 (b) 的 secret
4. 复制 `templates/ci/unity-tests.yml` → `.github/workflows/unity-tests.yml`，替换 `<TEST_PROJECT>`
5. 先手动 `workflow_dispatch` 跑通一个模块，再铺开到其余模块
