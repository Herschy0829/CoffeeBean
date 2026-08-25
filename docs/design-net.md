# CoffeeBean 网络模块设计（com.coffeebean.net）

> 版本：v0.2（设计定稿，已确认决策）
> 状态：待实施

---

## 1. 定位与独立性

| 项 | 决策 |
|----|------|
| 包名 | `com.coffeebean.net`（程序集 `CoffeeBean.Net`，命名空间 `CoffeeBean.Net`） |
| 依赖 | **`com.coffeebean.tools`**（首个消费者：MainThreadDispatcher 主线程回调 / CLog 日志 / CJson 编解码 / CSingletonMono） |
| Core 集成 | 可选（Bridge 条件编译，注册服务进 ServiceRegistry） |
| 其他模块依赖 | 无（不依赖业务模块） |

> 本模块是"工具模块作为公共底座"规则的第一个落地案例：网络回调天然在多线程，正好复用 tools 的主线程调度与日志。

## 2. 核心能力

### 2.1 HTTP 客户端 `CHttpClient`（UnityWebRequest 封装）
- GET / POST / PUT / DELETE，表单与原始字节
- **JSON 自动编解码**（组合 `CJson`）：`SendAsync<TReq, TResp>` / `SendAsync<TResp>`
- 超时、重试（可配次数与退避）、取消（CancellationToken）
- 回调保证**主线程**（`MainThreadDispatcher.RunOnMainThread`）
- 下载/上传进度事件
- **错误分类**：`CNetCode`（成功 / 网络错误 / 超时 / 服务器错误(4xx/5xx) / 解析失败 / 已取消）
- 公共 Header 设置（如 token）、Base URL

### 2.2 TCP 客户端 `CTcpClient`（Socket）
- 异步连接 / 断开 / 自动重连（指数退避）
- **帧协议**：4 字节长度头 + 载荷（解决粘包/拆包），见 `CNetFrame`
- 发送队列（后台线程发送，主线程入队 API）
- 接收线程 → `CNetFrame` 解析 → 主线程回调（`RunOnMainThread`）
- **心跳**：定时发送 Ping，超时判定断线
- 连接状态事件：Connected / Disconnected / Reconnecting

### 2.3 WebSocket 客户端 `CWsClient`（实时推送）
- 基于 **System.Net.WebSockets.ClientWebSocket**（内置，无第三方依赖；Windows/macOS/iOS/Android 可用）
- 文本（JSON）与二进制消息收发；连接/重连/心跳
- 回调保证主线程
- 注意：**WebGL 平台不支持 ClientWebSocket**，需后续单独实现 JS 桥接（记录在案，v1 不阻塞）

### 2.4 消息编解码 `CNetProtocol`（JSON + 二进制双编解码）
- **`INetCodec` 可插拔**，运行时按连接选择：
  - `CJsonNetCodec`：JSON 编解码（对齐 HTTP 与 TCP 文本消息）
  - `CBinaryNetCodec`：二进制编解码（长度前缀载荷透传为 byte[]，消息体字节布局由业务协议定义）
- **自定义 TCP 协议**：帧协议 + 可插拔编解码器由模块提供；具体消息体（字节布局/字段）由业务方实现
- 请求/响应配对（请求 ID + 回调表）；服务器主动推送按消息 ID 分发到订阅回调

### 2.5 会话
- **v1 仅连接层**：连接 / 发送 / 接收 / 心跳 / 重连；登录态与业务协议由业务层自行管理
- 预留 `CNetSession` 接口，后续版本再实现登录态/重连恢复

## 3. 线程模型

```
业务代码（主线程）
   │  SendAsync(...) / Send(...)        ← 主线程 API
   ▼
CHttpClient / CTcpClient / CWsClient
   │  网络 I/O（后台线程 / UnityWebRequest 异步）
   ▼
完成/收到消息 → MainThreadDispatcher.RunOnMainThread(callback)
   ▼
业务回调（主线程，可安全操作 Unity API）
```

- 所有对外回调**保证主线程**（复用 tools 的 `MainThreadDispatcher`）
- 内部线程只做 I/O 与协议解析，不碰 Unity API

## 4. 命名与目录结构（沿用 C 前缀 + 类别分组）

```
Runtime/
├── Http/          CHttpClient、CHttpRequest、CNetCode
├── Tcp/           CTcpClient、CNetFrame（帧协议）、CNetPacket
├── WebSocket/     CWsClient
├── Protocol/      CNetProtocol（编解码）、INetCodec、CJsonNetCodec、CBinaryNetCodec
├── Core/          CNetConfig（超时/重试/心跳参数）
└── Bridge/        与 Core 的可选集成
Tests/
├── Protocol/      帧协议粘包拆包、双编解码（纯逻辑可测）
├── Http/          错误分类、URL 拼接、重试逻辑（I/O 用假传输层）
└── Tcp/           心跳计时、重连策略（假传输层）
```

## 5. 错误模型

```csharp
public enum CNetCode
{
    Success = 0,
    NetworkError,     // 网络不可达 / 连接断开
    Timeout,          // 请求超时
    ServerError,      // HTTP 4xx/5xx 或对端返回错误
    ParseError,       // 响应解析失败
    Cancelled,        // 主动取消
    NotConnected,     // 未连接就发送
}
```

统一 `CNetException`（携带 code + 详情），配合 `CLog` 记录。

## 6. 测试策略（保持"可测试"理念）

| 层 | 方式 |
|----|------|
| 帧协议 / 编解码 | **纯逻辑单测**：粘包/拆包、长度头边界、JSON 编解码往返 |
| 错误分类 / 重试 / 心跳 | 逻辑单测（可注入时间/假传输层） |
| 网络 I/O | 抽象 `INetTransport`，测试用假传输模拟成功/失败/超时；可选本机回环 TCP 集成测试（PlayMode） |

## 7. 实施阶段

| Phase | 内容 |
|-------|------|
| 0 | 仓库骨架 + 依赖 tools + 目录结构 |
| 1 | `CHttpClient`（UnityWebRequest + JSON + 错误分类 + 重试/取消） |
| 2 | `CTcpClient` + `CNetFrame`（粘包拆包 + 心跳 + 重连） |
| 3 | `CNetProtocol`（编解码 + 推送分发）+ 可选 Session |
| 4 | Bridge 集成 + **NetDemo 示例**（HTTP 请求演示 + 本机回环 TCP 演示） |
| 5 | 测试补全 + 文档 + 发布（GitHub Release） |

## 8. 已确认决策

| 决策 | 结论 |
|------|------|
| 通信范围 | **HTTP + TCP + WebSocket**（WS 用内置 ClientWebSocket，WebGL 后续单独桥接） |
| 服务器协议 | **自定义 TCP 协议**：帧协议 + 可插拔编解码器由模块提供，消息体由业务实现 |
| 消息格式 | **JSON + 二进制双编解码**，运行时按连接切换（`INetCodec`） |
| 会话管理 | **v1 仅连接层**，登录态/业务协议由业务层管理，预留 `CNetSession` 接口 |
| 依赖 | `com.coffeebean.tools`（首个消费者：主线程回调 / 日志 / JSON） |
