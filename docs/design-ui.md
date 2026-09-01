# CoffeeBean UI 模块设计（com.coffeebean.ui）

> 版本：v0.1（草案，待确认）
> 状态：待实施
> 参考：QFramework UIKit + CodeGenKit（MIT），已精读源码吸收设计

---

## 1. 背景

### 1.1 Idle 现状（AyFarme/UIFarme）

- `UIMgr`（Singleton）：8 层 UI（Main/View/Dialog/Front/Guide/Tips/Top/WorldToScreen），双字典（打开过/正在显示），条件显示 + 等待队列，预加载，AB/Addressable 双加载路径
- `UIBase`：`UIShow/UIHide/PreLoad` 生命周期、`OnShow` 虚方法、DOTween 滑动动画
- `GenUIPanelCode`（Editor）：按预制体生成面板代码（字段引用），**整文件生成无分离**，重新生成会覆盖手写逻辑

**痛点**：条件显示逻辑复杂（isMustOrCan）；与资源层/业务强耦合（MainCamera/UI_Main）；代码生成无两文件分离；无栈式导航；无统计。

### 1.2 QFramework UIKit + CodeGenKit（已精读）

| 组件 | 设计 |
|------|------|
| `UIKit` | 静态门面：`OpenPanel<T>/ClosePanel/ShowPanel/HidePanel/GetPanel/Back/Stack`，`PanelSearchKeys` 对象池分配 |
| `UIManager` | 面板加载/生命周期编排（Single/Multiple 两种 OpenType） |
| `UIPanel` | 抽象基类：`Init/Open/Show/Hide/Close` + `OnInit/OnOpen/OnShow/OnHide/OnClose` 虚方法；`OnClosed` 回调；`CloseSelf/Back` |
| `UIKitConfig` | 加载器池 `IPanelLoaderPool`（默认 Resources，可插拔）、默认尺寸拉伸 |
| `UIRoot` | 单例，分层（Bg/Common/PopUI/CanvasPanel），分辨率设置，Overlay/Camera 模式 |
| `UIPanelTable` | 双索引表（GameObjectName/Type），`GetPanelsByPanelSearchKeys` |
| `UIPanelStack` | 栈式导航：Push（关闭当前）/Pop（重开上一个） |
| `CodeGenKit` | `Bind`/`AbstractBind` 标记组件 + `ViewController`；`UICodeGenerator` 生成 **`PanelName.cs`（用户）+ `PanelName.Designer.cs`（partial 自动）** 两文件；`UISerializer` 编译后（`[DidReloadScripts]`）自动挂载组件引用到 prefab |
| 模板 | `UIPanelTemplate`（主脚本：Data 类 + 生命周期空实现）、`UIPanelDesignerTemplate`（字段 + `ClearUIComponents` + Data 属性）、`UIElementCodeTemplate` |

**关键优势**：两文件分离（用户代码不被覆盖）、`Bind` 显式标记、编译后自动挂载、加载器可插拔、面板栈。

## 2. 模块定位

CoffeeBean UI 模块：**UGUI 面板管理 + 代码生成**，参照 QFramework UIKit/CodeGenKit 设计，CoffeeBean 化（C 前缀、统一 `CoffeeBean` 命名空间、UPM git 引用、Sample + 测试、可插拔加载器便于将来接 asset 模块）。

## 3. 设计（已按用户确认定稿）

### 3.1 决策

1. **依赖**：零额外依赖 + 可插拔加载器（`IPanelLoader` 默认 Resources 实现，将来可接 asset 模块 Addressables）
2. **层级**：QF 风格 6 层（`Bg/Common/PopUI/Guide/Toast/Top`），一个 `CUIRoot` 动态创建
3. **代码生成**：全量——`CBind` 标记 + `CPanel/Designer` 两文件分离 + Inspector 生成按钮 + 编译后自动挂载

### 3.2 命名空间与文件布局

统一 `CoffeeBean` 根命名空间（对齐框架约定），C 前缀：

```
Runtime/
├── CUIRoot.cs             UI 根（单例，6 层 RectTransform，分辨率/渲染模式）
├── CUIManager.cs          面板管理（加载/生命周期/Table/Stack）
├── CUIPanel.cs            面板抽象基类（CPanel）
├── CUIPanelData.cs        IUIData 接口 + CUIPanelData 基类
├── CUIPanelInfo.cs        面板信息（对象池）
├── CUIPanelSearchKeys.cs  打开参数（对象池）
├── CUIPanelTable.cs       双索引表
├── CUIPanelStack.cs       栈式导航
├── CUIPanelLoader.cs      加载器接口 + 池 + 默认 Resources 实现
├── CUISettings.cs         模块配置（命名空间/脚本目录/默认层级）
└── CUIComponent.cs        组件标记基类（CUIElement 派生）
Editor/
├── CUICodeGenerator.cs    代码生成器（菜单 + Inspector 按钮）
├── CUIPanelInspector.cs   面板 Inspector（生成代码按钮）
├── CUISerializer.cs       编译后自动挂载（[DidReloadScripts]）
└── CUICodeTemplates.cs    模板（主脚本/Designer/Element）
Tests/
└── ...                    核心逻辑测试
Samples~/
└── UIDemo/                面板打开/关闭/栈/传参演示 + 生成示例
```

### 3.3 CUIPanel（面板基类，对齐 QF UIPanel）

```csharp
public abstract class CUIPanel : MonoBehaviour, IUIPanel
{
    // 生命周期（UIManager 驱动）
    public void Init(IUIData uiData = null);        // -> OnInit
    public void Open(IUIData uiData = null);        // -> OnOpen，状态 Opening
    public void Show();                             // SetActive(true) -> OnShow
    public void Hide();                             // 状态 Hide -> OnHide -> SetActive(false)
    public void Close(bool destroy = true);         // -> OnClose -> 卸载/回收 loader -> Destroy

    protected virtual void OnInit(IUIData uiData) {}
    protected virtual void OnOpen(IUIData uiData) {}
    protected virtual void OnShow() {}
    protected virtual void OnHide() {}
    protected virtual void OnClose() {}
    protected virtual void OnBeforeDestroy() {}

    public void OnClosed(Action onClosed);          // 关闭回调
    protected void CloseSelf();                     // 关闭自己
    protected void Back();                          // 返回上一个（栈）

    // 状态与信息
    public CUIPanelInfo Info { get; set; }
    public CUIPanelState State { get; set; }
    public Transform Transform => transform;
}
```

生命周期顺序（对齐 QF）：`OpenPanel` → `CreateUI`（加载/层级/Info/Table.Add/Init）→ `Open(uiData)` → `Show()`；`Close` → `OnClose` → `Hide` → 卸载。

### 3.4 CUIManager（面板管理）

- `OpenPanel(CUIPanelSearchKeys)` / `OpenPanelAsync`：Single（查 Table 复用）vs Multiple（每次新建）
- `ShowPanel/HidePanel/ClosePanel/CloseAllPanel/HideAllPanel/GetPanel`
- `CreateUI`：`Config.LoadPanel` → `Root.SetLevelOfPanel` → 默认尺寸 → Info 分配 → Table.Add → `panel.Init`

### 3.5 CUIRoot（层级根，QF 风格 6 层）

```csharp
public enum CUILevel { Bg, Common, PopUI, Guide, Toast, Top }
```

单例（DontDestroyOnLoad + 自动创建）：每层一个 RectTransform（满屏拉伸）；`SetLevelOfPanel(level, panel)` 按 `panel` 是否有 Canvas 决定挂 CanvasPanel 还是层级节点；`SetResolution` / `ScreenSpaceOverlay/Camera` 模式切换。

### 3.6 CUIPanelLoader（可插拔加载器，对齐 QF IPanelLoader）

```csharp
public interface ICUIPanelLoader
{
    GameObject LoadPanelPrefab(CUIPanelSearchKeys keys);
    void LoadPanelPrefabAsync(CUIPanelSearchKeys keys, Action<GameObject> onLoaded);
    void Unload();
}
public interface ICUIPanelLoaderPool { ICUIPanelLoader Allocate(); void Recycle(ICUIPanelLoader); }
// 默认：CResourcesPanelLoader（Resources.Load<GameObject>(keys.GameObjName)）
// 未来：接 asset 模块的 CAssetSystem（Addressables）
```

### 3.7 CUIPanelSearchKeys（对象池）

`PanelType / GameObjName(prefabName) / CUILevel / IUIData / Panel / OpenType(Single|Multiple)` —— 对象池复用（`Allocate/Recycle`）。

### 3.8 CUIPanelTable（双索引）

`GameObjectNameIndex` + `TypeIndex`（`Dictionary<TKey, List<IPanel>>`），`GetPanelsByPanelSearchKeys` 按 Type/名称/实例查询。

### 3.9 CUIPanelStack（栈式导航）

`Push(panel)`：记录 Info → Close → 从 Table 移除；`Pop()`：按 Info 重开（OpenUI）。`Back()`：关当前 → Pop。

### 3.10 代码生成（对齐 CodeGenKit）

**CBind 标记组件**（运行时）：

```csharp
// 标记要生成字段引用的节点
[AddComponentMenu("CoffeeBean/CBind")]
public sealed class CBind : MonoBehaviour
{
    public string Comment;              // 生成的字段注释
    public bool IsElement;              // 是否作为独立 CUIElement 子类生成（默认 false = 面板内字段）
    public string CustomComponentName;  // 显式指定绑定组件类型（默认按优先级推断）
}
```

**两文件生成**（`CUIPanelInspector` 上的"生成代码"按钮 / 右键菜单）：

```
UIPanelName.cs            （用户手写：生命周期空实现 + Data 类，仅首次生成）
UIPanelName.Designer.cs   （自动：partial 类，字段 + ClearUIComponents + Data 属性，每次重新生成）
```

Designer 模板（对齐 QF）：`[SerializeField] public Xxx FieldName;` + `ClearUIComponents()` 置空 + `Data` 属性（`mData ?? (mData = new XxxData())`）。

**编译后自动挂载**（`CUISerializer`，`[DidReloadScripts]`）：EditorPrefs 记录待挂载 prefab 路径 → 编译完成后按 Bind 标记反射填充序列化字段 → SaveAssets。

**组件类型推断**（对齐 AbstractBind 优先级）：ViewController > SkeletonAnimation > TMP > UGUI（ScrollRect/InputField/Button/Text/Image/Toggle/Slider/...）> Collider/Animator/Canvas/... > RectTransform > Transform。

### 3.11 与 Idle/Asset 模块的关系

- 不依赖 Idle 的 `UIMgr`/`UIBase`；新项目直接用本模块
- 加载器接口预留：asset 模块发布后提供 `CAssetPanelLoader`（Addressables）实现，一行切换
- 命名空间统一 `CoffeeBean`（`using CoffeeBean;` 即可用 `CUIPanel/CUIManager/CUIRoot/...`）

## 4. 测试计划

EditMode 测试（核心逻辑，不依赖真实 prefab 加载——用**测试面板类 + 内存 prefab**或 mock loader）：

1. **打开/关闭生命周期**：OpenPanel → OnInit/OnOpen/OnShow 依次调用；Close → OnClose/OnHide 调用顺序
2. **Single 复用**：同类型二次打开不新建（Table 复用，Open/Show 再触发）
3. **Multiple 新建**：每次打开都新建实例
4. **层级归属**：不同 CUILevel 面板挂到对应层级节点
5. **Table 查询**：按 Type / 名称 / 实例查询正确
6. **Stack Push/Pop**：Push 关闭当前并记录，Pop 重开上一个；Back 行为
7. **传参**：UIData 正确传递到 OnInit/OnOpen/Data 属性
8. **加载器可插拔**：mock loader 被调用、池回收
9. **CloseAll/HideAll**：全部关闭/隐藏
10. **对象池**：SearchKeys/Info 分配回收无泄漏（计数验证）

代码生成部分（Editor 测试）：模板输出字符串校验（字段/namespace/partial 关键字）、Bind 类型推断（可选）。

## 5. 版本规划

- **v0.1.0**：CUIRoot + CUIManager + CUIPanel + 生命周期 + Table/Stack + 加载器池 + 代码生成（CBind + 两文件 + Inspector 按钮 + 编译后挂载）+ UIDemo + 测试
- **v0.2.0（候选）**：asset 模块的 CAssetPanelLoader（Addressables）、面板动画/转场扩展、遮罩/点击穿透、统计面板

## 6. 依赖与风险

- **依赖**：仅 `com.coffeebean.tools`（单例/日志/对象池辅助，若 tools 已有）；测试/Sample 用 dev 工程
- **风险**：代码生成依赖 `[DidReloadScripts]` 时序（对齐 QF 已验证模式）；EditMode 测试避免真实 Addressables（用 mock loader）
- **测试环境**：dev 工程无新增包依赖；Sample 用 Resources 下 prefab 或运行时构造
