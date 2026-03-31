# TmkTranslationSDK 接入文档

<!-- AUTO_VERSION_BLOCK_START -->
> 当前文档适配版本：`v1.0.0`  
> 最近更新日期：`2026-03-24`  
> 版本说明：见 [ios_release_notes.md](./ios_release_notes.md)
<!-- AUTO_VERSION_BLOCK_END -->

## 1. 简介

`TmkTranslationSDK` 用于把业务侧采集的 PCM 音频接入实时翻译能力，并向业务侧回传：

- 识别文本
- 翻译文本
- 翻译后的 PCM 音频
- 通道状态与错误信息

当前主要覆盖两类场景：

- 现场收听：单路音频输入，持续接收识别、翻译与翻译音频
- 一对一：双声道音频输入，按左右声道区分不同说话方

## 2. 快速开始

### 2.1 支持信息与接入前置条件

| 项目 | 说明 |
| --- | --- |
| 最低系统版本 | `iOS 15.0+` |
| Swift 版本 | `Swift 5.0` |
| 真机支持 | `iPhone / iPad` 真机，`iphoneos`，当前主支持架构为 `arm64` |
| 模拟器支持 | `iPhone / iPad Simulator`，`iphonesimulator`；发布产物提供 iOS Simulator slice，当前默认验证架构为 Apple Silicon `arm64`，如需 Intel Mac 请以当次 release 产物中的 simulator slice 为准 |
| My Mac（Designed for iPad） | 可随 iPad App 在该模式运行；SDK 不提供独立 `macOS` / `Mac Catalyst` slice |
| 发布产物 | `TmkTranslationSDK.xcframework`，同时包含真机与模拟器 slice |

接入前需要准备的权限与配置：

1. 麦克风权限：宿主 App 必须在 `Info.plist` 中配置 `NSMicrophoneUsageDescription`。
2. 网络访问配置：如果联调环境使用 `HTTP`，宿主 App 需要按实际环境配置 ATS 例外。
3. 运行时权限申请：开始录音前，宿主 App 仍需主动申请录音权限。

示例：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要访问麦克风以采集实时语音</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

运行时权限申请示例：

```swift
AVAudioSession.sharedInstance().requestRecordPermission { granted in
    print("record permission=\(granted)")
}
```

说明：

- `NSAllowsArbitraryLoads` 只建议用于联调或测试环境。
- 生产环境优先使用 HTTPS；如需放行 HTTP，请改为精确域名白名单。

### 2.2 下载与集成

SDK 集成与安装：
推荐使用cocoapods进行安装SDK，在podfile文件添加如下代码：

```
source 'https://cdn.cocoapods.org/'
source 'https://github.com/timekettle/TmkTranslationSDK-iOS.git'

pod 'TmkTranslationSDK', '1.0.0-beta19'
```

### 2.3 初始化 SDK

通常在 `AppDelegate` 或应用启动早期完成初始化。

```swift
import TmkTranslationSDK

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let globalConfig = TmkTranslationGlobalConfig.Builder()
            .setAuth(appId: "your_app_id", secret: "your_app_secret")
            .setOnlineAuthContext(
                tenantId: "timekettle",
                externalUserId: "u001",
                installId: "device-001"
            )
            .setLogEnabled(true)
            .setDiagnosisEnabled(false)
            .setNetworkEnvironment(.dev)
            .build()

        TmkTranslationSDK.shared.sdkInit(globalConfig)
        return true
    }
}
```

`TmkTranslationGlobalConfig.Builder` 常用配置：

- `setAuth(appId:secret:)`
  - 设置 SDK 鉴权所需的应用标识与密钥。
- `setOnlineAuthContext(tenantId:externalUserId:installId:)`
  - 按需补充租户、用户或设备标识。
- `setLogEnabled(_:)`
  - 控制 SDK 控制台日志开关。
- `setDiagnosisEnabled(_:)`
  - 控制本地诊断文件开关。
- `setNetworkEnvironment(_:)`
  - 使用预置服务环境。
- `setNetworkBaseURL(_:)`
  - 直接指定服务地址；优先级高于 `setNetworkEnvironment(_:)`。

### 2.4 基础接入流程

推荐顺序：

1. `sdkInit`
2. `verifyAuth`
3. 按需调用 `getSupportedLanguages(_:)`
4. `createTmkTranslationRoom`
5. `createTranslationChannel`
6. `pushStreamAudioData`
7. `stop / closeRoom / destroy`

#### 1）调用鉴权

```swift
TmkTranslationSDK.shared.verifyAuth { result in
    switch result {
    case .success:
        print("鉴权成功")
    case .failure(let error):
        print("鉴权失败: \(error.code) \(error.message)")
    }
}
```

#### 2）按需获取支持语言

如需向用户展示可选语言，可在 `verifyAuth` 成功后主动调用：

```swift
TmkTranslationSDK.shared.verifyAuth { result in
    switch result {
    case .success:
        let cachedVersion: String? = nil

        TmkTranslationSDK.shared.getSupportedLanguages(
            version: cachedVersion,
            uiLocales: []
        ) { result in
            switch result {
            case .success(let response):
                print("version: \(response.version ?? "-")")
                let localeCodes = response.localeOptions.map(\.code)
                print("支持语言：\(localeCodes)")
            case .failure(let error):
                print("获取支持语言失败: \(error.code) \(error.message)")
            }
        }
    case .failure(let error):
        print("鉴权失败: \(error.code) \(error.message)")
    }
}
```

说明：

- `getSupportedLanguages(_:)` 依赖业务鉴权结果。
- 未完成鉴权时调用会直接返回失败，并提示先执行 `verifyAuth(_:)`。
- `version` 用于业务方自行做本地缓存比对；SDK 不缓存语言列表。
- `uiLocales` 为可选参数，默认传空，由服务端按默认语言返回展示文本。
- 如果需要指定 `uiLocales`，只应传入语言列表接口返回模型中的 `code` 值。

返回模型：

- `TmkSupportedLanguagesResponse`
  - `version`：服务端语言配置版本号。
  - `languages`：语言分组列表。
  - `localeOptions`：展平后的语言区域列表，便于直接展示和选择。
- `TmkSupportedLanguage`
  - `code`：语言码，例如 `en`。
  - `locales`：该语言下可选的区域/口音列表。
  - `nativeAccent` / `nativeLang`：语言自身的国家/地区与语言名称。
  - `uiAccent` / `uiLang`：按 `uiLocales` 显示的国家/地区与语言名称。
- `TmkSupportedLocale`
  - `code`：语言区域码，例如 `en-US`。
  - `nativeAccent` / `nativeLang`：该语言区域的原生展示信息。
  - `uiAccent` / `uiLang`：该语言区域在当前 UI 语言下的展示信息。

#### 3）创建房间

```swift
let room = TmkTranslationSDK.shared.createTmkTranslationRoom(
    sourceLang: "zh-CN",
    targetLang: "en-US",
    scenario: .toSpeech,
    roomId: nil,
    channelScenario: .listen,
    messageTunnel: .rtm
) { result in
    switch result {
    case .success(let room):
        print("房间创建成功，roomNo=\(room.channelDialogResponse?.roomNo ?? "-")")
    case .failure(let error):
        print("房间创建失败: \(error.message)")
    }
}
```

参数说明：

- `sourceLang`：输入音频语言，例如 `zh-CN`
- `targetLang`：目标语言，例如 `en-US`
- `scenario`：房间场景，常用 `.toSpeech`
- `roomId`：可选业务房间号；传 `nil` 时由服务端生成
- `channelScenario`：SDK 场景；现场收听传 `.listen`
- `messageTunnel`：文本结果回传通道，常用 `.rtm`

#### 4）创建通道

```swift
final class NowListeningHandler: TmkTranslationListener {
    func onRecognized(from engine: AbstractChannelEngine, result: TmkResult<String>, isFinal: Bool) {
        print("识别: \(result.data), final=\(isFinal)")
    }

    func onTranslate(from engine: AbstractChannelEngine, result: TmkResult<String>, isFinal: Bool) {
        print("翻译: \(result.data), final=\(isFinal)")
    }

    func onAudioDataReceive(from engine: AbstractChannelEngine,
                            result: TmkResult<String>,
                            data: Data,
                            channelCount: Int) {
        print("收到翻译音频，bytes=\(data.count), channels=\(channelCount)")
    }

    func onError(_ error: TmkTranslationError) {
        print("错误: \(error.code) \(error.message)")
    }

    func onEvent(name: String, args: Any?) {
        print("事件: \(name)")
    }

    func onStateChanged(from engine: AbstractChannelEngine, snapshot: TmkTranslationChannelStateSnapshot) {
        print("状态: \(snapshot.state.rawValue), reason=\(snapshot.reason.rawValue)")
    }
}

let listener = NowListeningHandler()

let channelConfig = TmkTranslationChannelConfig.Builder()
    .setRoom(room)
    .setScenario(.listen)
    .setMode(.online)
    .setSourceLang("zh-CN")
    .setTargetLang("en-US")
    .setPCMSampleRate(16_000)
    .setPCMChannels(1)
    .setMessageTunnel(.rtm)
    .build()

TmkTranslationSDK.shared.createTranslationChannel(channelConfig, listener: listener) { result in
    switch result {
    case .success(let channel):
        print("通道创建成功")
        _ = channel
    case .failure(let error):
        print("通道创建失败: \(error.code) \(error.message)")
    }
}
```

#### 5）推送 PCM 音频

```swift
channel.pushStreamAudioData(pcmData, channelCount: 1, extraChunk: nil)
```

要求：

- PCM 格式为 `16-bit little-endian`
- `channelCount` 必须与真实输入数据一致
- `pcmSampleRate`、`pcmChannels`、`sourceLang` 要与实际业务数据保持一致

#### 5）停止与释放

```swift
channel.stop()
room.closeRoom { result in
    print("closeRoom=\(result)")
}
TmkTranslationSDK.shared.destroy()
```

建议顺序：

1. `channel.stop()`
2. `room.closeRoom(...)`
3. 整个业务结束时调用 `destroy()`

### 2.5 一对一接入示例

一对一与现场收听的主要差异：

- 房间场景使用 `channelScenario: .oneToOne`
- 通道场景使用 `.setScenario(.oneToOne)`
- 上行 PCM 通常为双声道

示例：

```swift
let room = TmkTranslationSDK.shared.createTmkTranslationRoom(
    sourceLang: "zh-CN",
    targetLang: "en-US",
    scenario: .toSpeech,
    roomId: nil,
    channelScenario: .oneToOne
) { result in
    print(result)
}

let channelConfig = TmkTranslationChannelConfig.Builder()
    .setRoom(room)
    .setScenario(.oneToOne)
    .setMode(.online)
    .setSourceLang("zh-CN")
    .setTargetLang("en-US")
    .setPCMSampleRate(16_000)
    .setPCMChannels(2)
    .build()
```

如果业务需要做双声道合成与拆分，可直接使用 `TmkTranslationPCMTools`：

```swift
let stereo = TmkTranslationPCMTools.mixStereo16LE(
    left: leftPCM,
    right: rightPCM
)

let split = TmkTranslationPCMTools.splitStereoInterleaved16LE(stereoPCM)
let left = split?.left
let right = split?.right
```

## 3. 核心 API 说明

### 3.1 `TmkTranslationSDK`

职责：

- SDK 总入口
- 鉴权、建房、建通道
- 生命周期管理
- 诊断目录导出

常用接口：

- `sdkInit(_:)`
  - 初始化 SDK 全局配置。
- `verifyAuth(_:)`
  - 校验当前 SDK 是否可进入在线流程。
- `createTmkTranslationRoom(...) -> TmkTranslationRoom`
  - 创建房间对象，并异步回调最终建房结果。
- `createTranslationChannel(_:callback:)`
  - 创建翻译通道。
- `createTranslationChannel(_:listener:callback:)`
  - 创建翻译通道并预绑定监听器。
- `getSupportedLanguages(_:)`
  - 在 `verifyAuth(_:)` 成功后按需异步获取支持语言配置；支持传入 `version` 与 `uiLocales`，成功返回 `TmkSupportedLanguagesResponse`，失败返回统一错误。
- `getDiagnosisDirectoryURL() -> URL?`
  - 获取本地诊断目录 `sdk_diagnosis` 路径；仅在开启诊断且目录已存在时返回。
- `destroy()`
  - 释放 SDK 资源。

### 3.2 `TmkTranslationGlobalConfig`

职责：保存 SDK 全局配置。

关键字段：

- `appId`
- `appSecret`
- `tenantId`
- `externalUserId`
- `installId`
- `isLogEnabled`
- `isDiagnosisEnabled`
- `networkEnvironment`
- `networkBaseURL`

### 3.3 `TmkTranslationChannelConfig`

职责：描述通道场景、语言方向、音频格式与消息回传方式。

关键字段：

- `scenario`
- `room`
- `defaultMode`
- `sourceLang`
- `targetLang`
- `pcmSampleRate`
- `pcmChannels`
- `playbackAudioDataMode`
- `playbackAudioPullConfig`
- `messageTunnel`

常见配置：

```swift
let config = TmkTranslationChannelConfig.Builder()
    .setRoom(room)
    .setScenario(.listen)
    .setMode(.online)
    .setSourceLang("zh-CN")
    .setTargetLang("en-US")
    .setPCMSampleRate(16_000)
    .setPCMChannels(1)
    .setPlaybackAudioDataMode(.pullPlaybackAudioFrameRawData)
    .setPlaybackAudioPullConfig(.init(intervalMs: 10, lengthInByte: nil))
    .build()
```

### 3.4 `TmkTranslationRoom`

职责：

- 持有房间号与房间相关结果
- 对外提供房间关闭能力

常用属性：

- `channelDialogResponse`
- `roomScenario`
- `messageTunnel`

常用接口：

- `closeRoom(completion:)`

### 3.5 `TmkTranslationChannel`

职责：

- 承载单个翻译通道
- 接收上行 PCM
- 回调文本、音频、事件与状态

常用接口：

- `setTranslationListener(_:)`
- `pushStreamAudioData(_:channelCount:extraChunk:)`
- `sendAudioMetadata(vadStatus:channel:baseTraceId:)`
- `stop()`
- `currentRuntimeState()`
- `getTranslationMode()`
- `getScenario()`
- `getChannelEngineType()`

### 3.6 `TmkTranslationListener`

推荐业务侧优先实现以下接口：

- `onRecognized(from:result:isFinal:)`
- `onTranslate(from:result:isFinal:)`
- `onAudioDataReceive(from:result:data:channelCount:)`
- `onError(_:)`
- `onEvent(name:args:)`
- `onStateChanged(from:snapshot:)`

常用公开数据：

- `result.data`
- `result.srcCode`
- `result.dstCode`
- `result.isLast`
- `result.extraData["bubble_id"]`
- `result.extraData["channel"]`

`onEvent(name:args:)` 的 `args` 不一定总是 `TmkResult<String>`，当前公开行为如下：

- `online_started`：`args == nil`
- `online_stopped`：`args == nil`
- `online_runtime_state_changed`：`args` 为 `TmkTranslationChannelStateSnapshot`
- 其他在线事件：`args` 通常为 `TmkResult<String>`

#### `onEvent(name:args:)`

`onEvent(name:args:)` 用于接收在线通道的通用运行事件。建议业务侧先基于 `name` 分支，再按对应类型读取 `args`。

##### 当前公开事件名

| `name` | `args` 类型 | 作用 | 常见场景 |
| --- | --- | --- | --- |
| `online_started` | `nil` | 在线通道启动完成 | 建房、鉴权、引擎启动完成后 |
| `online_stopped` | `nil` | 在线通道已停止 | 业务主动停止或引擎结束后 |
| `online_runtime_state_changed` | `TmkTranslationChannelStateSnapshot` | 通道状态发生变化 | 启动、重连、失败、停止等 |
| `online_notification` | `TmkResult<String>` | 服务端通知类消息 | 通知、提示、状态广播 |
| `online_recognition_failure` | `TmkResult<String>` | 识别失败消息 | 服务端返回识别失败事件 |
| `online_tts_state` | `TmkResult<String>` | TTS 播放状态消息 | 播放开始、播放结束、状态切换 |
| `online_stream_message_parsed` | `TmkResult<String>` | 已解析的流消息 | 文本消息通道收到结构化消息 |
| `online_audio_metadata` | `TmkResult<String>` | 音频元数据事件 | 收到音频元数据包 |
| `online_stream_message_raw` | `TmkResult<String>` | 原始流消息事件 | 收到原始流消息包 |
| `online_network_quality` | `TmkResult<String>` | 网络质量统计 | RTC 网络质量变化 |
| `online_remote_audio_stats` | `TmkResult<String>` | 远端音频统计 | 远端音频丢包率统计 |
| `online_local_audio_stats` | `TmkResult<String>` | 本地音频统计 | 本地音频丢包率统计 |

说明：

- 事件名是当前 SDK 对外公开的稳定分支依据，建议业务侧优先按 `name` 做处理。
- 当 `args` 为 `TmkResult<String>` 时，字段说明参见下方 `3.7 TmkResult<T>`。
- 当 `args` 为 `TmkTranslationChannelStateSnapshot` 时，字段说明参见下方 `onStateChanged(from:snapshot:)`。
- `online_started` / `online_stopped` 当前没有附加载荷，`args` 为 `nil`。

##### `onEvent` 的典型处理方式

```swift
func onEvent(name: String, args: Any?) {
    switch name {
    case "online_started":
        print("通道已启动")
    case "online_runtime_state_changed":
        if let snapshot = args as? TmkTranslationChannelStateSnapshot {
            print(snapshot.state.rawValue, snapshot.reason.rawValue)
        }
    case "online_stream_message_parsed",
         "online_notification",
         "online_tts_state":
        if let result = args as? TmkResult<String> {
            print(result.data)
        }
    default:
        break
    }
}
```

#### `onStateChanged(from:snapshot:)`

`onStateChanged(from:snapshot:)` 用于接收通道状态快照。该回调只在状态确实发生变化时触发，不会在相同状态重复回调。

补充说明：

- `onStateChanged` 和 `onEvent(name: "online_runtime_state_changed", args: snapshot)` 当前会同时发出。
- 如果业务只关心状态变化，优先使用 `onStateChanged`。
- 如果业务希望统一从一个入口接收所有运行事件，再使用 `onEvent` 读取 `online_runtime_state_changed`。

##### `TmkTranslationChannelStateSnapshot` 字段说明

| 字段 | 类型 | 作用 | 当前可能取值 |
| --- | --- | --- | --- |
| `state` | `TmkTranslationChannelState` | 当前通道运行状态 | 见下方状态枚举表 |
| `reason` | `TmkTranslationChannelStateReason` | 进入当前状态的原因 | 见下方原因枚举表 |
| `code` | `Int?` | 与当前状态相关的统一错误码；没有错误时为空 | 可能为 `nil`，也可能为统一错误码，如网络不可用、会话过期、配置无效等 |
| `message` | `String` | 对当前状态的补充说明文本 | 一段可读文本，例如 `rtc connected state=...` |
| `isRecoverable` | `Bool` | 当前状态是否可恢复 | `true` / `false` |
| `updatedAt` | `Date` | 本次状态快照生成时间 | 当前回调触发时间 |

##### `state` 可能取值

| 值 | 含义 | 业务建议 |
| --- | --- | --- |
| `idle` | 未启动 | 初始态，通常等待业务开始创建通道 |
| `starting` | 启动中 | 可展示“正在连接/初始化” |
| `running` | 运行中 | 通道当前可正常工作 |
| `reconnecting` | 重连中 | 可展示“网络恢复中/正在重连” |
| `degraded` | 能力降级 | 通道未完全中断，但部分能力异常 |
| `stopping` | 停止中 | 可展示“正在结束” |
| `stopped` | 已停止 | 通道已结束，可清理业务状态 |
| `failed` | 已失败 | 当前通道无法继续，通常需要业务侧处理 |

##### `reason` 可能取值

| 值 | 含义 | 常见触发场景 |
| --- | --- | --- |
| `none` | 无明确原因 | 默认初始化快照 |
| `startRequested` | 已请求启动 | 调用开始流程后 |
| `started` | 已启动完成 | 启动成功 |
| `stopRequested` | 已请求停止 | 调用停止流程后 |
| `stopped` | 已停止 | 通道或 RTC 已退出 |
| `networkUnavailable` | 系统网络不可用 | 设备网络断开 |
| `networkRestored` | 系统网络恢复 | 设备网络恢复 |
| `rtcConnecting` | RTC 正在连接 | RTC 建链中 |
| `rtcConnected` | RTC 已连接或重连成功 | RTC 首次连接或重连成功 |
| `rtcInterrupted` | RTC 中断 | RTC 连接被打断 |
| `rtcLost` | RTC 丢失 | RTC 连接丢失 |
| `rtcKeepAliveTimeout` | RTC 保活超时 | RTC 心跳超时 |
| `rtcTokenRequested` | RTC 请求续期 token | RTC 主动请求续期 |
| `rtcTokenWillExpire` | RTC token 即将过期 | RTC 预警 token 将过期 |
| `sessionExpired` | 会话已过期 | token 无效、token 过期等 |
| `invalidConfiguration` | 配置无效 | 参数错误、通道配置不合法 |
| `permissionDenied` | 权限错误 | 权限未授予或系统拒绝 |
| `bannedByServer` | 被服务端封禁 | 服务端禁止访问 |
| `serviceRejected` | 被服务端拒绝 | 服务端拒绝加入或拒绝当前操作 |
| `messageChannelFailure` | 文本消息链路异常 | 文本消息通道工作异常 |
| `engineError` | 引擎内部错误 | 其他引擎级错误 |

##### `code` 的取值特点

- `code` 不是每次都有值，以下场景常见为非空：
  - 网络不可用
  - 会话过期
  - 配置无效
  - RTC 操作失败
  - 引擎初始化失败
- `code` 应作为错误分支判断的主依据。
- `message` 更适合日志或调试展示，不建议业务逻辑直接依赖 `message` 文本做判断。

##### `isRecoverable` 的使用建议

- `true`
  - 当前问题理论上可恢复
  - 常见于 `reconnecting`、部分 `degraded`
- `false`
  - 当前问题通常不能自动恢复
  - 常见于 `failed + sessionExpired`
  - 常见于 `failed + invalidConfiguration`
  - 常见于 `failed + bannedByServer`

业务建议：

1. 当 `state == .running` 时，视为链路可用。
2. 当 `state == .reconnecting` 且 `isRecoverable == true` 时，可展示“恢复中”而不是立刻结束会话。
3. 当 `state == .failed` 且 `isRecoverable == false` 时，应提示用户重试、重新建房，或重新初始化。

### 3.7 `TmkResult<T>`

`TmkResult<T>` 是 SDK 对识别、翻译、音频事件和部分运行事件的统一返回模型。当前 SDK 对外回调中，最常见的类型是 `TmkResult<String>`。

#### 字段说明

| 字段 | 类型 | 作用 | 当前实现中的常见取值 |
| --- | --- | --- | --- |
| `sessionId` | `Int` | 当前结果所属的会话片段标识。业务侧可用于把同一轮中间结果与最终结果关联起来。 | 文本识别/翻译时通常为服务端片段序号；音频和运行事件时通常为远端 `uid`；拿不到明确值时可能为 `0` |
| `data` | `T` | 当前回调的主体数据。 | 识别回调中为识别文本；翻译回调中为翻译文本；音频回调中固定为 `"translated_audio"`；事件回调中可能是文本、事件名，或字节数/状态标记 |
| `srcCode` | `String` | 源语言代码。 | 例如 `zh-CN`、`en-US`、`fr-FR`、`es-ES`；某些事件中如果消息本身带 `locale`，则优先取消息中的语言码 |
| `dstCode` | `String` | 目标语言代码。 | 通常为当前通道配置的目标语言，例如 `en-US`、`fr-FR` |
| `isLast` | `Bool` | 当前结果是否为本轮最终结果。 | `true` 表示最终结果；`false` 表示中间增量结果。音频回调和大多数通用运行事件当前固定为 `false` |
| `extraData` | `[String: Any]` | 附加上下文字段。 | 根据回调类型和事件名不同而不同，详见下文 |

#### `sessionId`

当前 SDK 中 `sessionId` 的来源分为三类：

1. `onRecognized` / `onTranslate`

- 优先使用服务端返回的 `sequence`
- 如果上游没有提供，则为 `0`

2. `onAudioDataReceive`

- 使用远端音频流的 `uid`

3. `onEvent`

- 文本消息类事件通常使用远端 `uid`
- 本地统计类事件可能使用固定值，例如 `online_local_audio_stats` 当前为 `0`

因此，`sessionId` 适合用来做“同一来源结果”的归并，但如果业务需要做“同一轮对话气泡”的归并，优先建议使用 `extraData["bubble_id"]`。

#### `data`

`data` 的含义由回调类型决定：

| 回调 | `data` 含义 | 当前实现中的常见取值 |
| --- | --- | --- |
| `onRecognized` | 识别文本 | 用户说话的中间识别文本或最终识别文本 |
| `onTranslate` | 翻译文本 | 对应目标语言的中间翻译文本或最终翻译文本 |
| `onAudioDataReceive` | 音频事件标识 | 固定为 `"translated_audio"`；真实 PCM 数据在回调参数 `data: Data` 中 |
| `onEvent(name:args:)` | 事件主体 | 可能是事件文本、事件名、字节数文本、统计标记字符串 |

当前 `onEvent` 中常见的 `data` 取值如下：

| `name` | `data` 取值 |
| --- | --- |
| `online_notification` | 优先为消息中的文本；如果没有文本，则为事件名 |
| `online_recognition_failure` | 优先为失败消息中的文本；如果没有文本，则为事件名 |
| `online_tts_state` | 优先为消息中的文本；如果没有文本，则为事件名 |
| `online_stream_message_parsed` | 优先为消息中的文本；如果没有文本，则为事件名 |
| `online_audio_metadata` | 元数据字节数的字符串，例如 `"128"` |
| `online_stream_message_raw` | 原始消息字节数的字符串，例如 `"256"` |
| `online_network_quality` | 固定为 `"network_quality"` |
| `online_remote_audio_stats` | 固定为 `"remote_audio_stats"` |
| `online_local_audio_stats` | 固定为 `"local_audio_stats"` |

#### `srcCode` 与 `dstCode`

- `srcCode`：表示当前结果的源语言
- `dstCode`：表示当前结果的目标语言

当前实现中：

1. 文本识别/翻译结果

- 如果上游结果带有语言字段，则优先使用上游值
- 如果上游结果没有提供，则回退到当前通道配置的语言

2. 音频回调

- `srcCode` 使用当前通道的源语言
- `dstCode` 使用当前通道的目标语言

3. 事件回调

- `srcCode` 优先使用事件消息中的 `locale`
- 如果事件消息没有 `locale`，则回退到当前通道源语言
- `dstCode` 当前实现中使用当前通道目标语言

常见取值是标准语言代码字符串，例如：

- `zh-CN`
- `en-US`
- `fr-FR`
- `es-ES`

#### `isLast`

`isLast` 用于标识本次回调是不是“该轮结果的最后一条”：

- `false`：中间增量结果，还可能继续收到同一轮的更新
- `true`：最终结果，本轮文本通常可以视为稳定

当前实现中的典型行为：

- `onRecognized`：跟随识别消息中的 `isFinal`
- `onTranslate`：跟随翻译消息中的 `isFinal`
- `onAudioDataReceive`：固定为 `false`
- 文本消息类 `onEvent`：如果事件消息里带 `is_end`，则使用该值；否则为 `false`
- 通用统计类 `onEvent`：固定为 `false`

#### `extraData`

`extraData` 是一个可选附加信息字典。业务侧读取时需要按需做类型转换，不要假设所有 key 都存在。

建议：

- 先判断 key 是否存在
- 对数字字段兼容 `Int`、`UInt`、`NSNumber`
- 对布尔字段兼容 `Bool`
- 对字符串字段按 `String` 读取

##### 文本识别/翻译回调中的 `extraData`

`onRecognized` / `onTranslate` 当前可能包含以下字段：

| key | 类型 | 作用 | 常见取值 |
| --- | --- | --- | --- |
| `bubble_id` | `String` | 同一轮对话气泡 ID，最适合用于前端归并同一轮识别和翻译结果 | 业务无须解析格式，只需原样使用 |
| `trace_id` | `String` | 链路追踪标识，适合日志关联 | 一段非空字符串 |
| `channel` | `String` | 声道/侧边标识 | 在一对一场景下常见为 `left`、`right`；现场收听场景可能为空 |

说明：

- 这三个字段都是可选的，不保证每次都返回
- `bubble_id` 缺失时，业务侧可以回退使用 `sessionId`

##### 音频回调中的 `extraData`

`onAudioDataReceive` 当前返回：

| key | 类型 | 作用 | 常见取值 |
| --- | --- | --- | --- |
| `uid` | `UInt` / `Int` / `NSNumber` | 远端音频流来源标识 | 远端用户或远端订阅流的 `uid` |

补充：

- 当前 `result.data` 固定为 `"translated_audio"`
- 真正的音频 PCM 数据在 `onAudioDataReceive(..., data: Data, channelCount: Int)` 的 `data` 参数里

##### 事件回调中的 `extraData`

当 `onEvent(name:args:)` 的 `args` 为 `TmkResult<String>` 时，`extraData` 会随事件类型不同而不同。

###### 1. 文本消息类事件

以下事件的 `extraData` 结构基本一致：

- `online_notification`
- `online_recognition_failure`
- `online_tts_state`
- `online_stream_message_parsed`

当前可能包含：

| key | 类型 | 作用 | 常见取值 |
| --- | --- | --- | --- |
| `uid` | `UInt` / `Int` / `NSNumber` | 远端消息来源标识 | 远端 `uid` |
| `stream_id` | `Int` | 流消息通道 ID | 正整数，如 `1`、`9` |
| `event` | `String` | 原始事件名 | 如 `translate_speech_to_speech`、`notification`、`recognition_failure`、`tts_playback_state` |
| `event_type` | `String` | SDK 归一化后的事件类型名 | `translateSpeechToSpeech`、`notification`、`recognitionFailure`、`ttsPlaybackState`，未知事件时可能为 `unknown(\"...\")` |
| `kind` | `String` | 文本子类型 | 常见为 `origin`、`translation`；也可能为空 |
| `trace_id` | `String` | 链路追踪标识 | 一段非空字符串 |
| `channel` | `String` | 声道/侧边标识 | 常见为 `left`、`right` |
| `locale` | `String` | 事件携带的语言代码 | 如 `zh-CN`、`en-US` |
| `text` | `String` | 事件原始文本 | 一段文本；可能为空 |
| `state` | `String` | 状态类事件的状态值 | 例如 `completed`；未提供时为空 |
| `is_end` | `Bool` | 事件是否结束 | `true` / `false` |
| `bubble_id` | `String` | 对话气泡 ID | 一段非空字符串 |

说明：

- 除 `uid`、`stream_id`、`event`、`event_type` 外，其余字段都可能缺失
- `event_type` 是 SDK 归一化后的字符串，不建议业务侧自行解析未知值，只建议做日志记录或简单分支

###### 2. 原始数据/统计类事件

`online_audio_metadata`

| 字段 | 当前取值 |
| --- | --- |
| `data` | 元数据字节数的字符串 |
| `sessionId` | 远端 `uid` |
| `extraData["uid"]` | 远端 `uid` |
| `extraData["metadata_size"]` | 元数据长度，`Int` |
| `extraData["payload_size"]` | 元数据长度，`Int` |
| `extraData["trace_id"]` | 可选链路 ID，`String` |

`online_stream_message_raw`

| 字段 | 当前取值 |
| --- | --- |
| `data` | 原始消息字节数的字符串 |
| `sessionId` | 远端 `uid` |
| `extraData["uid"]` | 远端 `uid` |
| `extraData["stream_id"]` | 流消息 ID，`Int` |
| `extraData["payload_size"]` | 原始消息字节数，`Int` |

`online_network_quality`

| 字段 | 当前取值 |
| --- | --- |
| `data` | 固定为 `"network_quality"` |
| `sessionId` | 远端 `uid` |
| `extraData["uid"]` | 远端 `uid` |
| `extraData["tx_quality"]` | 上行网络质量整数码 |
| `extraData["rx_quality"]` | 下行网络质量整数码 |

说明：

- `tx_quality` / `rx_quality` 当前由 SDK 直接透传整数值，不做二次映射

`online_remote_audio_stats`

| 字段 | 当前取值 |
| --- | --- |
| `data` | 固定为 `"remote_audio_stats"` |
| `sessionId` | 远端 `uid` |
| `extraData["uid"]` | 远端 `uid` |
| `extraData["audio_loss_rate"]` | 远端音频丢包率整数值 |

`online_local_audio_stats`

| 字段 | 当前取值 |
| --- | --- |
| `data` | 固定为 `"local_audio_stats"` |
| `sessionId` | 固定为 `0` |
| `extraData["audio_loss_rate"]` | 本地音频丢包率整数值 |

#### 使用建议

1. 文本 UI 归并优先使用 `bubble_id`

- `bubble_id` 存在时，优先用它把识别文本和翻译文本归并到同一个 UI 气泡
- `bubble_id` 不存在时，再回退到 `sessionId`

2. 不要把 `isLast == true` 当作“整个通道结束”

- 它只表示“当前这一轮文本/事件已经结束”
- 不表示整个房间或整个翻译通道已结束

3. `extraData` 按需读取，不要强依赖所有字段

- 不同场景、不同事件名、不同服务端消息结构下，可返回的 key 会不同
- 建议把 `extraData` 视为“增强信息”，而不是唯一主键来源

### 3.8 `TmkTranslationPCMTools`

常用接口：

- `mixStereo16LE(left:right:)`
- `mixMonoToStereo16LE(mono:isLeft:)`
- `splitStereoInterleaved16LE(_:)`

## 4. 诊断文件

开启方式：

```swift
let globalConfig = TmkTranslationGlobalConfig.Builder()
    .setDiagnosisEnabled(true)
    .build()
```

获取诊断目录：

```swift
guard let diagnosisDirectoryURL = TmkTranslationSDK.shared.getDiagnosisDirectoryURL() else {
    return
}
print(diagnosisDirectoryURL.path)
```

说明：

- 诊断开启后，SDK 会在本地生成 `sdk_diagnosis` 目录。
- 业务侧只需获取目录路径，并按自身需要读取、归档或分享目录内文件。
- 若未开启诊断，或目录尚未生成，`getDiagnosisDirectoryURL()` 返回 `nil`。

## 5. 错误处理建议

SDK 对外统一使用 `TmkTranslationError` 返回失败信息。建议接入方优先基于以下字段处理：

- `error.code`
- `error.constantName`
- `error.message`
- `error.category`

建议：

1. 用户可见层只展示通用错误文案，不直接透传底层服务返回内容。
2. 业务日志中记录 `code`、`constantName` 和必要上下文即可。
3. 不要在业务日志、埋点或 UI 中暴露密钥、鉴权信息、完整请求地址或其他敏感内容。
4. 如需排障，优先结合诊断目录中的文件和业务侧自身日志定位问题。

## 6. Demo 参考

- Demo 工程：`/Users/tmk/Desktop/项目/tmk-translation-sdk/iOS/TmkTranslationSDKDemo/TmkTranslationSDKDemo.xcodeproj`
- 现场收听参考：`/Users/tmk/Desktop/项目/tmk-translation-sdk/iOS/TmkTranslationSDKDemo/TmkTranslationSDKDemo/Test/NowListen`
- 一对一参考：`/Users/tmk/Desktop/项目/tmk-translation-sdk/iOS/TmkTranslationSDKDemo/TmkTranslationSDKDemo/Test/OneToOne`
