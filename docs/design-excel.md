# CoffeeBean Excel 配置表工具模块设计（com.coffeebean.excel）

> 版本：**v0.5.0**
> 状态：**已实施**——读取 / 27 种列类型（含 BigInteger、枚举生成、Unity 结构、字典）/ 严格类型校验 /
> 增量生成（模板版本感知）/ 两个编辑器窗口（配置表工具 + 类型映射说明）/ ExcelDemo，测试见 §7。
> purchase 自 v0.1.6 起依赖本模块。

---

## 1. 定位与独立性

| 项 | 决策 |
|----|------|
| 包名 | `com.coffeebean.excel`（程序集 `CoffeeBean.Excel.Editor`，命名空间 `CoffeeBean`） |
| 形态 | **Editor-only 工具模块**（Excel 解析 / 代码生成都在编辑器；运行时不读 xlsx） |
| 依赖 | `com.unity.nuget.newtonsoft-json`（**只为生成的 Getter** 服务，见 §5）+ 内置 MiniExcel 插件 |
| Core 集成 | 可选（Bridge 程序集 + `versionDefines`，装了就出现在 CoffeeBean Hub 里） |
| 运行时消费 | 生成产物（JSON + C# 数据类 + Getter）随业务工程走，运行时只读 JSON |

> **本模块自己不用 Newtonsoft**：`CExcelCellJson` 手写 JSON 文本，`CExcelJsonBackend` 用反射探测包在不在。
> 这样"没装 Newtonsoft"只会让**生成出来的代码**编译不过（并有明确提示），不会让 excel 工具本身编译不过。

## 2. 核心能力

### 2.1 读取层 `CExcelReader`（MiniExcel 封装）
- `Read(path, options)` → `CExcelReadResult`：`Columns` / `Rows` / `HeaderRowIndex` / `ColumnComments` / `Issues`
- **表头自动检测**：前 3 行中匹配"带类型后缀列名"最多的行作为表头（兼容"中文说明行 + 字段名行"双行表头）
- **列别名**：`ColumnAliases` 把中文表头等映射到规范列名
- **跳过策略**：空行、注释行（首列 `#` 开头）；`CExcelSheetName.IsSkippedSheet` 跳过名字含 sheet/debug 的 sheet
- **值类型**：MiniExcel 回读的单元格 CLR 类型（实测）——数字恒为 `double`、文本 `string`、日期 `DateTime`、布尔 `Boolean`。
  这条很重要：**Excel 数字格式只保留 15 位有效数字**，所以 `_b`（BigInteger）要求单元格用文本格式，否则会被科学计数法吃掉精度

### 2.2 类型系统 `CExcelTypeCatalog`（唯一数据源）

**27 种标量**，数组后缀 = 标量后缀 + `a`（`_i` → `_ia`）：

| 分组 | 后缀 → C# 类型 |
|------|----------------|
| 整数 | `_i` int、`_l` long、`_b` **BigInteger**、`_by` byte、`_sb` sbyte、`_sh` short、`_us` ushort、`_u` uint、`_ul` ulong |
| 小数 | `_f` float、`_d` double、`_dec` **decimal** |
| 布尔 | `_bool` bool |
| 文本 | `_s` string、`_c` char |
| 时间 / 标识 | `_time` DateTime、`_span` TimeSpan、`_guid` Guid |
| 枚举 | `_e`（表内生成）、`_e:类型`（引用已编译枚举）、`_flags` / `_flags:类型` |
| 结构（Unity） | `_v2` / `_v3` / `_v4`、`_quat`、`_color`、`_rect` |
| 复合 | `_kv` `Dictionary<string,string>` |

**为什么要有这张表**：后缀表原来散落在推断代码的常量与 if 链里，"窗口 / 文档 / 解析 / 生成"四处各写一遍必然漂移。
现在 `CExcelTypeCatalog` 是唯一数据源，窗口从它渲染、解析按它匹配、`CExcelTypeCatalogTests` 逐项核对
（每个 kind 恰好一条、后缀互不结尾、示例真能生成合法 JSON、块偏移 = 标量个数）。

**布局约定**：`CExcelFieldKind` 先列 27 个标量再列同序的 27 个数组，因此

```
IsArray(kind)        = kind >= IntArray
ElementKind(array)   = array - ScalarCount
```

有测试锁住"数组块偏移 == 标量个数"，加类型时错位会立刻红。

**后缀歧义防护**：所有后缀都是 `_` + 字母（`_` 只出现在第 0 位），因此**任何后缀都不可能是另一个后缀的结尾**，
`_u`/`_ul`/`_us`、`_b`/`_by`/`_bool`、`_s`/`_sb`/`_sh`/`_span` 互不抢匹配。

**无后缀兜底推断**（保守，故意不猜新类型）：
全整数 → int；超 int32 → long；含小数 → double；整列 `true/false` → bool；否则 string。
纯 `1/0` 的列算 **int**（int 优先于 bool）；超 long 的数字串仍是 **string**（想要大整数请显式写 `_b`）——
无后缀推断一旦"变聪明"，老表的字段类型会悄悄变，所以宁可保守。

### 2.3 枚举（`_e` / `_e:类型` / `_flags`）

两种模式，统一成"成员名 → 数值"，所以 JSON 生成 / 校验 / 窗口预览只有一条代码路径：

| 模式 | 列名写法 | 行为 |
|------|----------|------|
| 生成 | `State_e` | 生成 `public enum 表名+字段名`（如 `BuildingState`），放在该表的数据类文件里 |
| 引用 | `State_e:MyEnum` | 引用**已编译**的枚举（不生成）；生成时按实际枚举校验类型与成员是否存在 |

- **自动编号**：不带值的取值从 0 起按**首次出现顺序**编号（`max(已用值)+1`）
- **显式值**：`green_3` → `Green = 3`。拆分规则是**按最后一个下划线拆**，尾巴能当整数才算值 ——
  所以 `fire_dragon` 整个是名字，`green_3` 会拆成 `green` + 3
- **成员名**：自动转 PascalCase（`green_leaf` → `GreenLeaf`）、数字开头补 `_`、C# 关键字加 `@`；
  被改名会出一条**警告**（让用户知道真名，否则照着原样写代码会编译不过）。
  引用模式则**要求与已编译名字完全一致**（区分大小写，不做任何转换）
- **校验（错误级，阻塞生成）**：
  - 同一枚举两个成员同值（用户点名要的"不能有同一枚举值"）
  - 同一名字被赋两个不同的值
  - 取值取不出合法成员名（没有字母）
  - 引用模式下类型找不到 / 成员不存在（报错会**列出可用成员**）
  - 枚举列一个取值都没有（C# 枚举不能为空）
- **章节表**：同一 `前缀_数字` 组内各章节**取并集后统一编号**（不是各建一套再合并 ——
  那样同一成员会在不同章节拿到不同值）。枚举类型用章节前缀命名（`ChapterConfigState`），
  定义写在基类文件里，各章节共用一个
- **跨表重名**：一次生成里同名的枚举类型成员必须一致（否则生成的 C# 会 CS0101 重复定义），
  由 `CExcelEnumRegistry` 在**同一文件内和跨文件**都拦下
- **JSON 里存数字**（成员值）。所以枚举在 JSON 里不可读是有意的：换来的是不需要任何转换器、改成员名不影响数据

### 2.4 校验层 `CExcelTableValidator`

生成之前每个单元格都按列声明的类型**真解析一遍**，解析不了就报错并中止该表（含 Excel 行号 + 列名）。

存在的理由：以前 `Level_i` 填 `abc` 会被**安静地写成 0**，`Gold_b` 被 Excel 记成科学计数法会变成完全不同的数 ——
这类"静默错数据"比编译错误难查得多。

- 开关：`CExcelGenerateOptions.StrictTypeCheck`（默认 true；窗口里有勾选框，老表迁移期可临时关掉）
- 另外给一条 `_b` 迁移提示：`_b` 列的值全是 `true/false` 时警告"这看起来是旧版 bool 用法，请改用 `_bool`"
- **同名字段检查**：两个列名去掉后缀后撞成同一个字段名（`State_e` + `State_ea`，`Name_s` + `Name_i`）
  → 生成的数据类会有两个同名字段 + 两个同名枚举类型（CS0102 / CS0101），报错完全看不出根因，所以在生成前拦住
- 主键列空着 → 错误（关掉 `SkipRowsWithoutKey` 时才会走到这里；开着的话这些行已经被丢掉了）

### 2.4.1 真实配置表的两个现实（拿一个真项目 28 张表 dogfood 出来的）

**① 数组分隔符必须包含 `_`。** 真实表里数组几乎都写成 `13_100`（id_数量）、`0.2_0.8_1`、`18_5_1_300_11_1_13_100`，
字符串数组也这么写（`6006_1`）。默认分隔符集合 = `;,|_；，｜`，可配置
（`CExcelGenerateOptions.ArraySeparators`）：字符串数组的元素本身含下划线时（`fire_dragon;ice_wolf`）把 `_` 去掉即可。
两条不可协商的边界：

| 类型 | 元素分隔符 | 为什么 |
|------|-----------|--------|
| 数值 / 字符串 / 布尔 / 时间 | 可配置集合（默认含 `_`） | 真实写法 |
| 向量 / 四元数 / 颜色 / 矩形 | 只有 `;` 和 `\|` | 元素内部就是逗号（`1,2` 是一个二维向量） |
| 字典数组 `_kva` | 只有 `\|` | 元素内部键值对用 `;` / `,` |
| 枚举数组 `_ea` | `;` `,` `\|`，**不认 `_`** | `_` 是"名字_值"语法，`green_3` 不能被拆开 |
| `[Flags]` 数组 `_flagsa` | `;` `,`（`\|` 留给元素内部位组合） | `Cold\|Hot;Cold` 是 2 个元素，不是 3 个 |

**② 表里有说明行 / 图例行 / 草稿块。** 真实表头下面往往还有一段"字段 | 说明"的图例，或者某列旁边贴一串临时算的数
（实测一张 44 行的表里 30 行是这种）。它们**主键是空的**。处理：

- 自动选主键时**优先选"每行都是合法值"的第一列**（真正的键列通常如此），没有才退回"第一个可做键的列"
- 主键为空/非法的行**跳过**（`CExcelGenerateOptions.SkipRowsWithoutKey`，默认开），出**警告并列出被跳过的行号**
- 跳完一行不剩 → 报错（多半是表头检测选错行），**不生成空表**
- 关掉这个开关时，主键为空 = 错误（有行没有主键的配置表没有意义）

### 2.5 生成层 `CExcelGenerator`

```
输出目录/                              # 代码（默认 Assets/Configs/Generated）
├── Building.cs                        # 强类型数据类 + 该表用到的枚举定义
├── BuildingGetter.cs                  # 加载器（Resources → Newtonsoft → List + 主键查询）
└── CoffeeBean.Generated.asmdef        # 独立程序集（改表只重编译这一小个程序集）
Resources/Configs/
└── Building.json                       # 表数据 {"data":[...]}（可 XOR 混淆加密）
```

- **字段名**：列名去后缀转 PascalCase（`Level_i` → `Level`、`State_e:MyEnum` → `State`）
- **Getter**：`All` 懒加载 + `Get(主键)` 字典查询；主键列可配置，默认第一个"可做键"的列
- **多章节**（sheet 名 `前缀_数字`）：每章节一份 JSON/子类/Getter + 共用的基类 + 一个聚合 Getter
  （`Chapters` / `ChapterN` / `GetByID(id, chapterId)` / `GetChapter(chapterId)`）
- **增量生成** `CExcelIncrementalGenerator`：状态 = **模板版本 + 文件修改时间**（EditorPrefs）。
  带模板版本是因为：只比 mtime 的话，升级框架后模板变了但 Excel 没改会被一直跳过，
  产物永远停在旧模板。`CExcelGenerator.TemplateVersion` 一变，全部表自动重新生成
- **一次运行内缓存读结果**：章节表要读两遍（建枚举并集 + 生成），缓存避免重复解析

## 3. JSON 后端：为什么是 Newtonsoft

生成的 Getter 用 `Newtonsoft.Json.JsonConvert` 反序列化。原因是实测（`CExcelJsonBackendTests` 锁住）：

| 类型 | JsonUtility | Newtonsoft |
|------|-------------|------------|
| BigInteger / decimal / DateTime / TimeSpan / Guid / `Dictionary` / **Rect** | ✗ 全都读不回来（`{}`） | ✓ |
| Vector2/3/4 / Quaternion / Color | ✓ | ✓ |
| 数组 | ✓（部分） | ✓ |

也就是说：**只要支持 BigInteger（用户明确要求）就必然要换后端**；换了之后 decimal / 时间 / Guid / 字典 / Rect 一起解锁。
不做双后端：一条代码路径，不会出现"窗口说支持、生成器不认"。

两个实现细节踩过坑，写在这里免得再踩：

1. **JSON 文本是手写的，不用 Newtonsoft 序列化**。`JsonConvert.SerializeObject(new Vector3(1,2,3))`
   会因 `Vector3.normalized`（返回 Vector3）自引用直接抛
   `Self referencing loop detected for property 'normalized'`；Rect 同理（`center`/`min`/`max`/`size`）。
   所以 `CExcelCellJson` 手写 JSON（顺带能保证 BigInteger 是裸数字、枚举是数字、日期是 ISO），
   Newtonsoft 只负责**反**序列化。
2. **生成的 Wrapper 必须是 public**：`Newtonsoft` 要能构造它，私有嵌套类型不可靠。
   `[System.Serializable] public sealed class Wrapper { public List<T> data; }` 嵌套在 Getter 里，
   既不污染命名空间，又能被 Newtonsoft 实例化。

还有一条精度纪律：`BigInteger` 的反序列化对**科学计数法是有损的**
（`1.23456789012346E+19` → `12345678901234599936`），所以 `_b` 只接受纯整数文本，
遇到 `E`/`.` 直接报错并提示"把该列设成文本格式"，绝不静默写个错的数。

## 4. 单元格语法速查

| 类型 | 写法 | 备注 |
|------|------|------|
| 整数 | `123` / `-5` | 超范围报错 |
| `_b` | `12345678901234567890` | 单元格必须是**文本格式** |
| `_dec` | `1.23` | |
| `_bool` | `true` / `false` / `1` / `0` | 不分大小写 |
| `_c` | `A` | 只能一个字符 |
| `_time` | `2026-09-18 10:30:00` | 也认 Excel 日期单元格、`2026/9/18` |
| `_span` | `01:30:00` | 也认 `1.02:03:04`（天.时:分:秒） |
| `_guid` | `6f9619ff-8b86-d011-b42d-00c04fc964ff` | |
| `_e` | `green` / `green_3` | 见 §2.3 |
| `_flags` | `Fire|Ice` | 也认 `,` `;` |
| `_v2/_v3/_v4` | `1,2` / `1,2,3` / `1,2,3,4` | 逗号分隔 |
| `_quat` | `0,0,0,1` 或 `0,90,0` | 4 个数 = (x,y,z,w)；3 个数 = 欧拉角 |
| `_color` | `#FF8800` / `255,136,0` / `1,0.5,0,1` | 整数且有一个 > 1 → 按 0~255；否则按 0~1 |
| `_rect` | `0,0,100,50` | x,y,width,height |
| `_kv` | `atk=10;hp=20` | 数组用 `|` 分组（`_kva`） |
| 数组（通用） | `13_100` / `1;2;3` / `1,2` | 分隔符 `;` `,` `|` `_`（含中文全角）；向量/颜色/矩形只能用 `;`/`|`；空单元格 → 空数组 |

**空单元格 → 确定性默认值**：数值 0、字符串空串、字符 `\0`、时间零值、结构全 0、枚举 0、数组空数组。

## 5. 编辑器窗口

| 窗口 | 入口 | 用途 |
|------|------|------|
| Excel 配置表工具 | Window > CoffeeBean > Excel · Excel 配置表工具 | 文件夹批量增量生成、生成选项、严格校验开关、后端状态 |
| 类型映射说明 | Window > CoffeeBean > Excel · 类型映射说明 | **活文档**：从 `CExcelTypeCatalog` 渲染后缀表 + 枚举语法 + 规则 + 规划中类型（可整表复制成纯文本） |
| 单文件校验/预览 | 主窗口列表行"预览/校验" | 选 sheet → 看表头/列类型/问题 → 真校验（含类型校验）/ 生成此 sheet |

## 6. 目录结构

```
Editor/
├── CoffeeBean.Excel.Editor.asmdef
├── Core/        CExcelReader、CExcelModels、CExcelSheetName、CExcelValue、CExcelTestFactory、CExcelJsonBackend
├── Infer/       CExcelTypeInfer(CExcelFieldKind)、CExcelTypeCatalog、CExcelEnumDef(成员/构建/解析/登记)
├── Generate/    CExcelGenerator、CExcelCellJson、CExcelTableValidator、CExcelIncrementalGenerator、CExcelCrypto
├── Window/      CExcelToolsWindow、CExcelFileWindow、CExcelTypeMappingWindow
└── Plugins/     MiniExcel.dll 等（Editor-only 插件）
Runtime/Bridge/  CoffeeBean.Excel.Bridge.asmdef（仅 core 存在时编译：注册进 CoffeeBean Hub）
Tests/           Core / Infer / Generate 三层
```

## 7. 测试策略

| 层 | 方式 |
|----|------|
| 读取 | 用 MiniExcel **写出测试用 xlsx**（临时文件），断言行/列/表头/别名/跳过 |
| 类型表 | 每个 kind 恰好一条、后缀互不结尾、数组块偏移、示例真能生成合法 JSON、字段名去后缀 |
| 后端能力 | **逐类型真反序列化**：单元格示例 → JSON → `JsonConvert.DeserializeObject(json, 真实Type)` → 断言值；并锁"JsonUtility 读不回哪些" |
| 枚举 | 自动编号/显式值/拆分规则/成员名规范化 + 全部校验分支（同值、同名不同值、非法名、引用模式、跨表重名、章节并集） |
| 校验 | 坏值必须报错并给出**行号 + 列名**；`StrictTypeCheck=false` 时降级；空值不算错；同名字段生成前拦截 |
| 真实表长相 | `_` 分隔数组、说明行/图例行跳过（警告列行号）、全表主键无效报错不产空表、主键回落到"每行都合法"的列 |
| 生成 | 生成到临时目录 → 断言 JSON 可被 Newtonsoft 读回、C# 类/Getter/枚举文本、多章节产物、模板版本标记 |
| **产物真编译** | 生成产物丢进 dev 工程 `Assets/` 下编译（这条抓到过"含 `_kv` 的表少了 using System.Collections.Generic"）|
| 窗口 | 手工验证（Hub 入口 + 交互） |

> 生成产物的"能编译"由两条路径保证：① 产物真丢进 dev 工程编译（模板改动的必过项）；
> ② 产物写在业务工程 `Assets/` 下时 Unity 会真编译（用户工程 dogfood）。

### 7.1 一个实测到的 Unity 行为（踩过一次，记下来）

**普通 asmdef 会自动引用插件 DLL**（`overrideReferences: false` 时 Newtonsoft、MiniExcel 都拿得到），
**但测试程序集拿不到** —— `optionalUnityReferences: ["TestAssemblies"]` 的 asmdef 编译时不会自动引用插件，
`using Newtonsoft.Json` 直接 CS0246。

所以 excel 的测试**不直接引用 Newtonsoft**，而是通过编辑器程序集里的 `CExcelJsonBackend`（反射调用
`JsonConvert.DeserializeObject<T>`）走真实反序列化。顺带好处：excel 的**编译**不依赖 Newtonsoft，
只有**生成出来的**代码依赖它 —— 没装包时用户能看到窗口里的红字提示，而不是一个看不懂的编译错误。

## 8. 关键决策记录

| 决策 | 结论 | 理由 |
|------|------|------|
| 形态 | Editor-only | 运行时只读生成产物 |
| 解析库 | MiniExcel（内置插件 dll） | 复用 purchase 现有，轻量 |
| JSON 后端 | **Newtonsoft（单后端）** | BigInteger 等类型 JsonUtility 读不回；双后端必然漂移 |
| JSON 文本 | **手写** | Newtonsoft 序列化 Unity 结构会自引用死循环 |
| `_b` | **BigInteger**（破坏性变更） | 用户要求"大数字用 biginteger"；bool 让位给 `_bool` |
| 枚举表示 | JSON 存数字 | 不需要转换器；改成员名不影响数据 |
| 缺值 | 确定性默认值 | 生成的 JSON 永远合法 |
| 坏值 | **报错**（默认） | 静默写 0 是最难查的错 |
| 数组分隔符 | 默认含 `_`，可配置 | 真实表里 `13_100` 是主流写法；字符串数组元素含 `_` 时把 `_` 去掉 |
| 无主键行 | **跳过 + 警告列行号**（默认） | 真实表里有说明行/图例行/草稿块；跳完不剩则报错，不产空表 |
| 产物验证 | 断言文本 **+ 真编译** | "生成文本里有 …"不等于能编译（`_kv` 的 using 就是这么漏的） |
| 增量状态 | 模板版本 + mtime | 否则升级框架后产物停在旧模板 |
| 命名 | 类 `C` 前缀；生成的枚举 = 表名 + 字段名 | 与框架一致；避免跨表重名 |
