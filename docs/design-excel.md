# CoffeeBean Excel 配置表工具模块设计（com.coffeebean.excel）

> 版本：v0.1（草案，待确认）
> 状态：**已实施（v0.1.0，2025）**——CExcelReader / CExcelTypeInfer / CExcelGenerator（JSON + C# 类 + Getter）/ 工具窗口 / ExcelDemo 已实现并发布；测试 27 个（EditMode）；purchase 0.1.6 已迁移依赖

---

## 1. 定位与独立性

| 项 | 决策 |
|----|------|
| 包名 | `com.coffeebean.excel`（程序集 `CoffeeBean.Excel`，命名空间 `CoffeeBean.Excel`） |
| 形态 | **Editor-only 工具模块**（Excel 解析 / 代码生成均在编辑器，运行时不直接读 xlsx） |
| 依赖 | **无（独立模块）**——纯 Editor 工具，无运行时程序集 / 无 Core Bridge（无服务可注册） |
| 运行时消费 | 生成产物（JSON + C# 数据类 + Getter）随业务工程走，运行时只读 JSON（配合 tools `CJson`） |

> 对齐游戏项目既有方案（Excel2Json2CSharp：ExcelDataReader → JSON + C# 数据类 + DataGetter），
> CoffeeBean 版改用 MiniExcel（purchase 已用，轻量 ~490KB），并把 purchase 的成熟解析经验（表头检测/列别名/警告分级）泛化进来。

## 2. 核心能力

### 2.1 读取层 `CExcelReader`（MiniExcel 封装）
- `Read(path, options)` → `CExcelReadResult`：
  - `Rows`：`List<Dictionary<string, object>>`（列名 → 规范化值：数字/字符串/布尔）
  - `Columns` / `HeaderRowIndex`：表头位置
- **表头自动检测**（purchase 经验泛化）：前 3 行中匹配"规范列名后缀约定"最多的行作为表头
  （支持"中文说明行 + 字段名行"双行表头）
- **列别名**：`Id_s / ID_i / 商品ID` 等别名映射到规范列名
- **跳过策略**：空行、注释行（首列以 `#` 开头）、无主键行（警告级）
- `CExcelIssue`（错误/警告分级）：缺列 = 错误（阻塞），类型不一致 = 警告，空表 = 错误

### 2.2 类型推断 `CExcelTypeInfer`
- **列名后缀显式声明类型**（对齐 purchase 表与游戏项目约定）：

| 后缀 | 类型 | 后缀 | 类型 |
|------|------|------|------|
| `_i` | int | `_ia` | int[] |
| `_l` | long | `_la` | long[] |
| `_f` | float | `_fa` | float[] |
| `_d` | double | `_da` | double[] |
| `_b` | bool | `_ba` | bool[] |
| `_s` | string | `_sa` | string[] |

- **无后缀兜底推断**：全列整数 → int；含小数 → float；含布尔字面量 → bool；否则 string
- 数组分隔符：`;`（支持中文 `；`）与 `,`

### 2.3 生成层 `CExcelGenerator`
输入：一张表（列名 + 类型 + 行数据）+ 生成选项；输出三件产物：

```
输出目录/
├── ChapterConfig.json               # 表数据（JSON 数组，运行时 Resources 加载）
├── ChapterConfig.cs                 # 强类型数据类（字段 + 属性，无 Unity 依赖）
└── ChapterConfigGetter.cs           # 加载器（Resources → CJson → List + 按主键查询）
```

- **数据类**：类名 = 表名（PascalCase）；字段 = 规范列名（去类型后缀，下划线转驼峰）
- **Getter**：`All` 懒加载列表 + `Get(主键)` 字典查询（主键列可配置，默认第一列 `*_i/_l/_s`）
- 选项：输出目录、命名空间、主键列、是否生成 JSON / 类 / Getter
- 批量：`GenerateFolder(folder)` 处理目录下全部 `.xlsx`（跳过 `~$` 临时文件）

### 2.4 编辑器窗口 `CExcelToolsWindow`（Window > CoffeeBean > Excel Tools）
- 选表（单个或目录）→ 预览（表头行 / 列名+推断类型 / 行数 / 问题列表）
- 配置生成选项 → 生成 / 批量生成 → 报告产物路径与问题
- 打包前监听（可选，仿 purchase IapBuildHook）：勾选后构建前强制重生成失败中止

### 2.5 与 purchase 的迁移（v0.1 同步）
- `com.coffeebean.purchase` 的 `ExcelImporter` 重构为基于 `CExcelReader`（读取/表头/别名/警告分级走 excel 模块），
  purchase 保留 IAP 特有逻辑（ConsumeType 映射、商店 ID 校验、IapConfig 生成）→ **purchase 0.1.6 依赖 excel 模块**
- purchase 的 `ExcelTestFactory` 保留（purchase 特有产物测试）

## 3. 目录结构

```
Runtime/（无——纯 Editor）
Editor/
├── CoffeeBean.Excel.Editor.asmdef
├── Core/           CExcelReader、CExcelReadOptions、CExcelReadResult、CExcelIssue
├── Infer/          CExcelTypeInfer、CExcelFieldKind
├── Generate/       CExcelGenerator、CExcelGenerateOptions、CExcelGenerateResult、CSharpTemplate
├── Window/         CExcelToolsWindow
└── Plugins/        MiniExcel.dll 等（Editor-only 插件）
Tests/
├── CoffeeBean.Excel.Tests.asmdef
├── Core/           读取/表头检测/别名/跳过/问题分级
├── Infer/          类型推断（后缀/兜底/数组）
└── Generate/       生成产物断言（JSON 合法/C# 类可编译/Getter 逻辑）
```

## 4. 测试策略

| 层 | 方式 |
|----|------|
| 读取 | 用 MiniExcel **写出测试用 xlsx**（临时文件），断言行/列/表头/别名/跳过（EditMode） |
| 推断 | 纯逻辑：后缀表全组合 + 无后缀兜底 + 数组分隔符 |
| 生成 | 生成到临时目录 → 断言 JSON 合法（CJson）、C# 类**编译检查**（写入 asmdef 临时工程或纯文本断言）、Getter 用假 Resources 数据测查询 |
| 窗口 | 不动（手工验证） |

> 代码生成产物验证：生成到 dev 工程临时目录 → 触发编译（跑测试本身编译整个工程）→ 验证生成类可编译。

## 5. 实施阶段

| Phase | 内容 |
|-------|------|
| 0 | 仓库骨架（package.json / Editor asmdef / MiniExcel 插件迁移 / README / CHANGELOG） |
| 1 | 读取层 `CExcelReader` + 表头检测/别名/跳过 + 测试 |
| 2 | 类型推断 `CExcelTypeInfer` + 测试 |
| 3 | 生成层 `CExcelGenerator`（JSON + C# 类 + Getter）+ 测试（含生成类编译验证） |
| 4 | 编辑器窗口 `CExcelToolsWindow` + ExcelDemo 示例（样例表 + 生成演示） |
| 5 | **purchase 迁移**：ExcelImporter 重构基于 excel 模块（purchase 0.1.6） |
| 6 | 全量验证 + 发布（excel v0.1.0 + purchase v0.1.6 + core registry + 游戏 manifest） |

## 6. 已确认决策

| 决策 | 结论 |
|------|------|
| 形态 | **Editor-only**（运行时只读生成产物，不直接读 xlsx） |
| 独立性 | 独立模块，无依赖 / 无 Core Bridge（纯 Editor 工具无运行时面） |
| 解析库 | MiniExcel（复用 purchase 现有，轻量） |
| 列类型约定 | 后缀显式声明（`_i/_l/_f/_d/_b/_s` + 数组 `_ia...`），无后缀推断兜底 |
| 生成产物 | JSON + C# 数据类 + Getter（三件套），Getter 走 Resources + CJson |
| purchase | v0.1.6 迁移为依赖 excel 模块（ExcelImporter 重构） |
| 命名 | 类 `C` 前缀（`CExcelReader` 等）；接口 `I` 前缀 |
