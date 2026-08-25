# CoffeeBean

模块化 Unity 框架：**一个模块 = 一个 GitHub 仓库 = 一个独立功能**。任何游戏工程通过 Unity Package Manager 的 Git 引用接入模块，由 Core 模块统一管理模块的安装 / 卸载 / 升级 / 依赖 / 版本兼容。

## 仓库结构

```
CoffeeBean/                      # 框架根仓库（本仓库）
├── docs/
│   └── design.md                # 框架设计文档（先读这个）
├── packages/                    # 各模块的开发 checkout（各自独立 git 仓库）
│   ├── com.coffeebean.core/     #   Core 模块：注册/引导/服务注册/模块管理
│   └── com.coffeebean.events/   #   类型安全事件总线（首个验证模块）
├── templates/
│   └── module/                  # 新模块脚手架（复制即用）
└── dev/                         # 本地联调 Unity 工程（不入库）
```

> `packages/` 与 `dev/` 已被 `.gitignore` 忽略：每个模块在 `packages/` 下是独立的 git 仓库，各自推送各自的 GitHub 仓库。

## 模块列表

| 模块 | 功能 | Git 引用 |
|------|------|----------|
| `com.coffeebean.core` | 模块管理 / 引导 / 服务注册 | `https://github.com/Herschy0829/com.coffeebean.core.git#v0.1.11` |
| `com.coffeebean.events` | 事件系统（EventBus 轻量 + EventCenter 受管） | `https://github.com/Herschy0829/com.coffeebean.events.git#v0.2.1` |
| `com.coffeebean.purchase` | 内购（Unity IAP 5.4，Excel 配置，可选服务器核销） | `https://github.com/Herschy0829/com.coffeebean.purchase.git#v0.1.5` |
| `com.coffeebean.tools` | 工具模块（单例 / 主线程调度 / 线程池，独立无依赖） | `https://github.com/Herschy0829/com.coffeebean.tools.git#v0.4.1` |

## 快速开始（游戏工程侧）

1. 新建 Unity 工程（Unity 6 / 6000.x）
2. 编辑 `Packages/manifest.json`，添加：

   ```json
   {
     "dependencies": {
       "com.coffeebean.core": "https://github.com/Herschy0829/com.coffeebean.core.git#v0.1.11"
     }
   }
   ```

3. 等待 UPM 解析完成后，打开 `Window > CoffeeBean > Module Manager` 一键安装其他模块
4. 入口场景创建一个空物体，挂上 `CoffeeBeanBootstrap` 组件 → 框架自动引导

## 本地多仓库联调开发

在 `packages/` 下 clone 各模块仓库，然后打开 `dev/` Unity 工程（它已通过 `file:` 路径引用本地模块）。修改模块代码立即生效，无需重新拉取。

## 新建一个模块

复制 `templates/module/` 到 `packages/`，按 `PLACEHOLDERS.md` 替换占位符，推送自己的 GitHub 仓库，然后在根仓库的模块清单（`com.coffeebean.core/Editor/Resources/coffeebean.registry.json`）里登记。

## 文档

- 框架设计：`docs/design.md`（架构、模块规范、版本约定、实施路线）

## License

[MIT](LICENSE.md)
