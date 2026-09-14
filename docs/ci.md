# CI（持续集成）

> 状态：**工作流已就位，本地等价流程已验证通过；真正在 GitHub 上跑起来只差授权 secret。**
> 工作流：`.github/workflows/unity-tests.yml`（框架根仓库）

## 1. 为什么 CI 放在根仓库，而不是各模块仓库

设计文档 `design.md` §9 当初规划的是"每个模块仓库配 Unity Test Runner"。实施时发现按本仓库布局**做不到**：

| 位置 | 是否是 Unity 工程 | 能否独立跑测试 |
|---|---|---|
| 框架根仓库 | ✅ 含 `dev/`（消费工程） | ✅ |
| `packages/<模块>` | ❌ 只是 UPM 包 | ❌ |

模块仓库里只有 `package.json` + `Runtime/`，没有工程文件；测试必须在一个**消费工程**里跑。
能跑测试的消费工程是 `dev/` —— 它通过 `file:` 引用各模块，且 `manifest.json` 的 `testables` 已登记全部包。

所以：**把 `dev/` 纳入根仓库版本控制**（已完成），CI 在根仓库跑；各模块仓库不再各配一份重复工程。

## 2. 已完成的改动

| 改动 | 说明 |
|---|---|
| `dev/` 入库 | 只排除生成物（`Library/` `Temp/` `obj/` `Logs/` `UserSettings/` `TestResults/`）。共 200 个文件 / 1.4 MB —— 若把 `Library/`+`TestResults/` 也提交会多出约 300 MB |
| `scripts/run-editmode-tests.ps1` | 本地跑 EditMode 测试，等价于 CI 做的事 |
| `.github/workflows/unity-tests.yml` | 根仓库的 CI 工作流 |

### 已验证：干净 checkout 能构建并通过全部测试

用 `git worktree` 取出**仅被追踪的文件**（模拟一次全新 clone），再把 17 个模块复制进 `packages/`，
对 `dev/` 跑完整 EditMode 套件：

```
TOTAL=461 PASSED=461 FAILED=0 SKIPPED=0 RESULT=Passed
```

这证明了 **`dev/` 所需的文件全部在版本控制里**，没有遗漏（例如漏提交 `.meta`、Addressables 配置或 `ProjectSettings`）。

> ⚠️ 未验证的部分：`unity-tests.yml` 这个 YAML **本身从未在 GitHub Actions 上跑过**
> （本地无法执行 Actions）。它依赖的每个动作（clone → 构建 → 跑测试）都已用上述方式在本地等价验证。

## 3. 启用前还差什么

**只差一样：Unity 授权 secret。**

### (a) Unity 授权 secret —— 必需

在根仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret | 必需 | 说明 |
|---|---|---|
| `UNITY_LICENSE` | ✅ | Unity 授权文件（`.ulf`）内容 |
| `UNITY_EMAIL` | 可选 | 用账号密码激活时需要 |
| `UNITY_PASSWORD` | 可选 | 同上 |

未配置时工作流**优雅跳过**（打印一条 notice），不会让 push 变红。

获取 `.ulf`：本地激活一次 Unity 后从 `C:\ProgramData\Unity\Unity_lic.ulf` 取内容，或按
game-ci 的[激活文档](https://game.ci/docs/github/activation)用 Docker 生成。

### (b) 模块仓库可见性 —— 已满足，无需配置

工作流的 clone 步骤：public 仓库直接 `git clone` 即可，**不需要**任何 token。

已核实（2026-09-14，GitHub API）：根仓库与全部 17 个模块仓库**都是 public**。

> 注：`design.md` §11 记录的是"根/Core/events/purchase 保持私有"，该状态**已过时** —— 这些仓库后来已转公开。
> 若将来有模块仓库改回 private，则需额外配 `MODULE_CLONE_TOKEN`（有读权限的 PAT）：
> 默认的 `GITHUB_TOKEN` 只能访问当前仓库，**不能**用来 clone 其他私有仓库。

### (c) Actions 分钟数

Unity 镜像较重。工作流已用 `actions/cache` 缓存 `dev/Library/` 降低重复构建成本。
私有仓库按分钟计费，公开仓库免费。

## 4. 模块版本只有一处真相

工作流**不硬编码**各模块版本：它先拉 `core`（`CORE_TAG`，唯一需要在此维护的版本号），
再从 core 内置的模块目录 `coffeebean.registry.json` 读出每个模块的 `latest` tag 逐个 clone。

这样"模块版本"只在 registry 里维护一次，避免 README / registry / CI 三处漂移
（框架里已经踩过这个坑：`asset` 的 Bridge 版本一度落后 `package.json` 两个版本）。

## 5. 本地跑测试

```powershell
# 全部 EditMode
pwsh -File scripts/run-editmode-tests.ps1

# 只跑某个模块
pwsh -File scripts/run-editmode-tests.ps1 -Assembly CoffeeBean.Build.Tests
```

脚本里用 `Start-Process` + `Wait-Process` 而非 `& Unity.exe`：**Unity.exe 是 GUI 子系统程序**，
用 `&` 调用会立即返回，既拿不到退出码也等不到结果文件。

> 脚本文件带 UTF-8 BOM。Windows PowerShell 5.1 会把无 BOM 文件按 ANSI 读，中文会解析失败。

## 6. 附：MemoryPack 依赖的评估结论

`com.coffeebean.save` 依赖 `com.cysharp.memorypack`。曾考虑"改用上游 git URL 取代本地 vendored 副本"，
调研后**结论是不改**，原因如下。

上游 README 明确要求 Unity 侧装**两样**：

1. 用 [NuGetForUnity](https://github.com/GlitchEnzo/NuGetForUnity) 从 NuGet 装 `MemoryPack`
   （提供 `MemoryPack.Core.dll` 运行时 + `MemoryPack.Generator.dll` **源生成器**）
2. 再引 git URL 装 `MemoryPack.Unity` 胶水包：
   `https://github.com/Cysharp/MemoryPack.git?path=src/MemoryPack.Unity/Assets/MemoryPack.Unity#1.21.4`

已用 GitHub API 核实：该 git URL 指向的目录**只有** `Runtime/`（3 个文件）+ `package.json`，
**不含任何 DLL，也不含源生成器**。

也就是说 git URL 只覆盖了第 2 步。若只做这一步而移除本地副本，`MemoryPack.Generator.dll` 缺失会导致
所有 `[MemoryPackable]` 类型**编译失败**（save 模块的测试数据就是这类）。

当前 `dev/Packages/com.cysharp.memorypack` 正是"胶水 + NuGet 解包 DLL"的合并副本，其中
`MemoryPack.Generator.dll.meta` 带 `RoslynAnalyzer` 标签（Unity 靠它把 DLL 当源生成器）。
由于 `dev/` 现已入库，这份副本也随之纳入版本控制，CI 能正常取到 —— 因此**无需**再拆分。

若将来确实要换成上游 git URL，则必须同时决定源生成器从哪来（引入 NuGetForUnity，或只把 DLL 单独 vendored），
不能只改 manifest 里的那一行。
