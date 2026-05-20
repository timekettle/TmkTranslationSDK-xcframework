# TmkTranslationSDK iOS API 文档

<!-- AUTO_VERSION_BLOCK_START -->
> 当前文档适配版本：`v1.0.0`  
> 最近更新日期：`2026-04-18`  
> 版本说明：见 [ios_release_notes.md](./ios_release_notes.md)
<!-- AUTO_VERSION_BLOCK_END -->

## 1. 简介

`TmkTranslationSDK` 用于将业务侧采集的 PCM 音频接入翻译能力，并向业务侧返回：

- 识别文本
- 翻译文本
- 翻译后的 PCM 音频
- 通道状态与错误信息
- 诊断日志与离线模型状态

当前 SDK 同时支持：

- 在线翻译
- 离线翻译
- 收听模式（单声道）
- 一对一模式（双声道）

本文面向外部接入方，重点说明：

- SDK 初始化与鉴权
- 在线/离线接入流程
- 所有公开接口与数据模型
- 常见使用方式与注意事项

---

## 2. 接入前准备

### 2.1 环境要求

| 项目 | 说明 |
| --- | --- |
| 最低系统版本 | `iOS 15.0+` |
| Swift 版本 | `Swift 5.x` |
| 真机架构 | `arm64` |
| 模拟器 | 以发布产物包含的 simulator slice 为准 |
| 发布产物 | `TmkTranslationSDK.xcframework` |

### 2.2 权限要求

宿主 App 需要声明麦克风权限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要访问麦克风以采集实时语音</string>
```

如果联调环境使用 HTTP，还需要按实际情况配置 ATS 例外。生产环境建议只使用 HTTPS

```xml
<key>NSAppTransportSecurity</key>
	<dict>
	  <key>NSAllowsArbitraryLoads</key>
	<true/>
</dict>
```

### 2.3 安装示例

推荐使用 CocoaPods：

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/timekettle/TmkTranslationSDK-iOS.git'

pod 'TmkTranslationSDK', '1.0.0'
```

如具体发布版本与本文不一致，请以发布说明为准。

---

## 3. 核心流程总览

### 3.1 在线翻译

在线模式典型流程：

1. `sdkInit`
2. `verifyAuth`
3. `getSupportedLanguages(source: .online)`
4. `createTmkTranslationRoom`
5. `createTranslationChannel`
6. `pushStreamAudioData`
7. `stop / closeRoom / releaseChannel / destroy`

### 3.2 离线翻译

离线模式典型流程：

1. `sdkInit`
2. `verifyAuth`
3. `isOfflineTranslationSupported`
4. `getSupportedLanguages(source: .offline)`
5. `isOfflineModelReady` 或 `downloadOfflineModels`
6. `createTranslationChannel`（`config.mode = .offline`）
7. `pushStreamAudioData`
8. `stop / releaseChannel / destroy`

### 3.3 回调线程说明

SDK 对外的大多数异步回调都会切回主线程后再回调业务方，包括：

- `verifyAuth`
- `getSupportedLanguages`
- `createTmkTranslationRoom`
- `createTranslationChannel`
- `closeRoom`

监听器 `TmkTranslationListener` 的回调会切回主线程后再回调业务方，可直接用于更新 UI。

离线模型下载监听器 `TmkOfflineModelDownloadListener` 的回调同样会切回主线程。

### 3.4 在线与离线的主要区别

| 项目 | 在线翻译 | 离线翻译 |
| --- | --- | --- |
| 是否依赖 `verifyAuth` | 是 | 建议先鉴权，用于确认离线能力 |
| 是否需要房间 | 需要 | 不需要 |
| 是否需要离线模型 | 不需要 | 需要 |
| 通道创建接口 | `createTranslationChannel` | `createTranslationChannel` |

---

## 4. 初始化与鉴权

## 4.1 `TmkTranslationSDK.shared`

SDK 入口是单例：

```swift
TmkTranslationSDK.shared
```

类型：`TmkTranslationSDK`

### 4.2 `sdkInit(_:)`

用于初始化 SDK 全局配置。

```swift
public func sdkInit(_ config: TmkTranslationGlobalConfig)
```

参数说明：

- `config: TmkTranslationGlobalConfig`
  - SDK 全局配置对象。

返回值：

- 无返回值。

行为说明：

- 只保存全局配置并初始化日志。
- 不会自动触发鉴权。
- 调用 `destroy()` 后，如需继续使用，必须重新调用 `sdkInit(_:)`。

示例：

```swift
let globalConfig = TmkTranslationGlobalConfig.Builder()
    .setAuth(appId: "your_app_id", secret: "your_app_secret")
    .setOnlineAuthContext(
        tenantId: "timekettle",
        externalUserId: "u001",
        installId: "device-001"
    )
    .setLogEnabled(true)
    .setDiagnosisEnabled(false)
    .setNetworkEnvironment(.test)
    .build()

TmkTranslationSDK.shared.sdkInit(globalConfig)
```

### 4.3 `verifyAuth(_:)`

执行在线/离线鉴权。

```swift
public func verifyAuth(_ callback: @escaping AuthCallback)
```

参数说明：

- `callback`
  - 鉴权回调。
  - 成功：`.success(())`
  - 失败：`.failure(TmkTranslationError)`

返回值：

- 无返回值。

行为说明：

- 首次调用时会懒初始化网络监听、诊断和鉴权基础设施。
- 在线翻译必须先鉴权成功。
- `verifyAuth(_:)` 内部会先执行在线鉴权；在线鉴权成功后，SDK 会继续尝试离线鉴权，用于更新离线能力状态。
- `verifyAuth(_:)` 的回调成功/失败只由在线鉴权结果决定；离线鉴权失败不会导致本次 `verifyAuth(_:)` 回调失败。
- 离线翻译建议先鉴权，再通过 `isOfflineTranslationSupported()` 判断当前账号是否支持离线能力。
- 离线翻译并不是完全零前置条件可直接使用：至少需要先成功鉴权一次、离线能力开关已开启、且相关离线模型曾下载成功。

示例：

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

### 4.4 `isOfflineTranslationSupported()`

查询当前鉴权结果是否支持离线翻译。

```swift
public func isOfflineTranslationSupported() -> Bool
```

返回值：

- `true`：当前鉴权上下文支持离线翻译。
- `false`：当前账号未开通离线翻译能力，或尚未完成离线鉴权。

注意：

- 建议在 `verifyAuth(_:)` 成功后再调用。
- `verifyAuth(_:)` 成功仅表示在线鉴权成功；如果离线鉴权未成功，当前接口仍可能返回 `false`。

---

## 5. 全局配置 `TmkTranslationGlobalConfig`

### 5.1 `TmkTranslationNetworkEnvironment`

SDK 内置环境枚举：

```swift
public enum TmkTranslationNetworkEnvironment: String {
    case dev
    case test
    case uat
    case pre
    case pre_jp
    case pre_us
}
```

建议：

- `dev` 仅用于开发调试，对外接入请优先使用 `test` 或 Timekettle 指定环境。
- `setNetworkBaseURL(_:)` 一般只用于联调或特殊接入，不建议线上随意切换。

### 5.2 `TmkTranslationGlobalConfig.Builder`

```swift
public final class Builder {
    public init()
    public func setAuth(appId: String, secret: String) -> Builder
    public func setOnlineAuthContext(tenantId: String? = nil,
                                     externalUserId: String? = nil,
                                     installId: String? = nil) -> Builder
    public func setLogEnabled(_ isEnabled: Bool) -> Builder
    public func setDiagnosisEnabled(_ isEnabled: Bool) -> Builder
    public func setNetworkEnvironment(_ environment: TmkTranslationNetworkEnvironment) -> Builder
    public func setNetworkBaseURL(_ url: URL) -> Builder
    public func setNetworkBaseURL(_ urlString: String) -> Builder
    public func build() -> TmkTranslationGlobalConfig
}
```

各接口说明：

#### `setAuth(appId:secret:)`

- `appId`
  - 业务鉴权 App ID。
- `secret`
  - 业务鉴权 App Secret。

必填。

#### `setOnlineAuthContext(tenantId:externalUserId:installId:)`

- `tenantId`
  - 可选，租户标识。
- `externalUserId`
  - 可选，业务用户 ID。
  - 如果传入，则优先级高于 `installId`。
- `installId`
  - 可选，设备/安装实例 ID。

#### `setLogEnabled(_:)`

- `true`：输出 SDK 控制台日志。
- `false`：关闭控制台日志。

#### `setDiagnosisEnabled(_:)`

- `true`：开启诊断日志与诊断文件采集。
- `false`：关闭诊断能力。

#### `setNetworkEnvironment(_:)`

- 设置预置环境。

#### `setNetworkBaseURL(_:)`

- 设置自定义服务端地址。
- 优先级高于 `setNetworkEnvironment(_:)`。

#### `build()`

- 生成不可变的 `TmkTranslationGlobalConfig`。

---

## 6. 支持语言接口

### 6.1 `TmkSupportedLanguagesSource`

```swift
public enum TmkSupportedLanguagesSource: Equatable {
    case online
    case offline
}
```

含义：

- `.online`：获取在线翻译支持的语言列表。
- `.offline`：获取离线翻译支持的语言列表。

### 6.2 `getSupportedLanguages(source:version:uiLocales:_:)`

```swift
public func getSupportedLanguages(
    source: TmkSupportedLanguagesSource,
    version: String? = nil,
    uiLocales: [String] = [],
    _ callback: @escaping (Result<TmkSupportedLanguagesResponse, TmkTranslationError>) -> Void
) -> TmkSDKCancellable?
```

参数说明：

- `source`
  - 语言列表类型，必填。
  - `.online` 表示在线翻译支持语言。
  - `.offline` 表示离线翻译支持语言。
- `version`
  - 可选，本地缓存版本号。
  - 在线模式下，若不传，SDK 会优先复用已缓存的版本号发起增量请求。
- `uiLocales`
  - 可选 UI 语言列表。
  - 用于控制返回的语言展示名称，例如优先显示中文名称。
- `callback`
  - 完成回调。

返回值：

- `TmkSDKCancellable?`
  - 可取消的请求句柄。
  - 若创建失败可能返回 `nil`。

行为说明：

#### 在线语言列表

- 不依赖鉴权；完成 `sdkInit(_:)` 后即可请求。
- 依赖网络可用；若当前无网络，在线语言列表请求会失败。
- SDK 会根据 `version` 尝试返回最新语言列表；当本次没有新的语言列表时，会优先返回本地已保存的列表。
- 如果本次获取失败，但本地已有可用语言列表，SDK 会优先返回本地列表；没有可用列表时才回调错误。

#### 离线语言列表

- 不依赖鉴权。
- 当 `uiLocales` 为空，或包含 `zh` 前缀时，离线语言名优先显示中文；否则显示原生语言名。
- 当前支持的离线语言如下：

| 语言 | code | 说明 |
| --- | --- | --- |
| 中文 | `zh` | 简体中文离线语言码 |
| 英语 | `en` | 英语离线语言码 |
| 日语 | `ja` | 日语离线语言码 |
| 韩语 | `ko` | 韩语离线语言码 |
| 法语 | `fr` | 法语离线语言码 |
| 西班牙语 | `es` | 西班牙语离线语言码 |
| 俄语 | `ru` | 俄语离线语言码 |
| 德语 | `de` | 德语离线语言码 |
| 意大利语 | `it` | 意大利语离线语言码 |
| 阿拉伯语 | `ar` | 阿拉伯语离线语言码 |
| 泰语 | `th` | 泰语离线语言码 |

示例：

```swift
// 在线语言列表
_ = TmkTranslationSDK.shared.getSupportedLanguages(source: .online,
                                                   uiLocales: ["zh-CN"]) { result in
    switch result {
    case .success(let response):
        print(response.version ?? "-")
        print(response.localeOptions.map(\.code))
    case .failure(let error):
        print(error.message)
    }
}

// 离线语言列表
_ = TmkTranslationSDK.shared.getSupportedLanguages(source: .offline,
                                                   uiLocales: ["zh-CN"]) { result in
    switch result {
    case .success(let response):
        print(response.localeOptions.map { "\($0.uiLang)(\($0.code))" })
    case .failure(let error):
        print(error.message)
    }
}
```

### 6.3 语言模型

#### `TmkSupportedLanguagesResponse`

```swift
public struct TmkSupportedLanguagesResponse {
    public let version: String?
    public let languages: [TmkSupportedLanguage]
    public var localeOptions: [TmkSupportedLocale]
}
```

字段说明：

- `version`
  - 语言配置版本号。
- `languages`
  - 按语言分组后的列表。
- `localeOptions`
  - 展平后的 locale 列表，适合直接用于语言选择 UI。

#### `TmkSupportedLanguage`

```swift
public struct TmkSupportedLanguage {
    public let code: String
    public let locales: [TmkSupportedLocale]
    public let nativeAccent: String
    public let nativeLang: String
    public let uiAccent: String
    public let uiLang: String
}
```

字段说明：

- `code`
  - 语言代码，例如 `en`。
- `locales`
  - 该语言下可选 locale 列表。
- `nativeAccent` / `nativeLang`
  - 原生展示名称。
- `uiAccent` / `uiLang`
  - 当前 UI 语言下的展示名称。

#### `TmkSupportedLocale`

```swift
public struct TmkSupportedLocale {
    public let code: String
    public let nativeAccent: String
    public let nativeLang: String
    public let uiAccent: String
    public let uiLang: String
}
```

字段说明：

- `code`
  - locale 代码，例如 `en-US` 或 `zh`。
- `nativeAccent` / `nativeLang`
  - 原生展示名称。
- `uiAccent` / `uiLang`
  - 当前 UI 语言下的展示名称。

---

## 7. 在线翻译：房间与通道

## 7.1 房间相关类型

### `TmkTranslationMessageTunnel`（仅在线翻译使用）

```swift
public enum TmkTranslationMessageTunnel: String, Equatable {
    case rtm
    case rtc
}
```

含义：

- `rtm`：通过 Agora RTM 接收识别/翻译文本。
- `rtc`：通过 Agora RTC stream message 接收识别/翻译文本。

一般建议使用 `rtm`。

说明：
- 该配置仅在线翻译使用。
- 离线翻译不使用 `TmkTranslationMessageTunnel`。

### `TmkRoomScenario`

```swift
public enum TmkRoomScenario {
    case recognize
    case toText
    case toSpeech
}
```

含义：

- `recognize`：语音识别
- `toText`：语音翻译到文本
- `toSpeech`：语音翻译到语音

实时翻译常用 `toSpeech`。

### `TmkTranslationRoomDialogResponse`

```swift
public struct TmkTranslationRoomDialogResponse {
    public struct TranslationItem {
        public let locale: String
        public let subscribeUid: String
    }

    public let connectUid: String
    public let roomNo: String
    public let speakerIdentityNo: String
    public let translationList: [TranslationItem]
}
```

字段说明：

- `connectUid`
  - 当前用户连接 UID。
- `roomNo`
  - 服务端房间号。
- `speakerIdentityNo`
  - 说话人身份号。
- `translationList`
  - 目标语言订阅列表。
  - 每项的 `subscribeUid` 表示对应语言音频流的订阅 UID。

### `TmkTranslationRoom`

`TmkTranslationRoom` 是在线翻译的房间容器。

公开属性：

- `channelDialogResponse: TmkTranslationRoomDialogResponse?`
  - 最近一次成功建房后的 dialog 快照。
- `roomScenario: TmkRoomScenario`
  - 当前房间业务场景。
- `messageTunnel: TmkTranslationMessageTunnel`
  - 当前文本消息通道。

公开方法：

```swift
public func closeRoom(completion: @escaping (Result<Void, TmkTranslationError>) -> Void) -> TmkSDKCancellable?
```

说明：

- 关闭当前房间。
- 只在在线翻译中使用。

### 7.2 `createTmkTranslationRoom(...)`

```swift
public func createTmkTranslationRoom(
    sourceLang: String = "en-US",
    targetLang: String = "zh-CN",
    scenario: TmkRoomScenario = .toSpeech,
    roomId: String? = nil,
    channelScenario: Scenario = .listen,
    messageTunnel: TmkTranslationMessageTunnel = .rtm,
    _ callback: @escaping CreateRoomCallback
) -> TmkTranslationRoom
```

参数说明：

- `sourceLang`
  - 源语言代码，例如 `zh-CN`。
- `targetLang`
  - 目标语言代码，例如 `en-US`。
- `scenario`
  - 房间业务场景，通常使用 `.toSpeech`。
- `roomId`
  - 可选业务房间号。
  - 传 `nil` 时由服务端生成。
- `channelScenario`
  - 通道场景。
  - 常用值：`.listen`、`.oneToOne`。
- `messageTunnel`
  - 文本消息通道。
- `callback`
  - 建房结果回调。

返回值：

- `TmkTranslationRoom`
  - 房间对象会立即返回。
  - 实际 dialog 数据通过 `callback` 异步补齐。

说明：

- 在线翻译必须先建房，再创建通道。

示例：

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
        print(room.channelDialogResponse?.roomNo ?? "-")
    case .failure(let error):
        print(error.message)
    }
}
```

---

## 8. 通道配置 `TmkTranslationChannelConfig`

### 8.1 `Scenario`

```swift
public enum Scenario {
    case presentation
    case listen
    case oneToOne
    case listenFar
}
```

说明：

- `listen`
  - 收听模式，单声道输入。
- `oneToOne`
  - 一对一模式，双声道输入。
- `presentation`、`listenFar`
  - 兼容保留场景，是否启用以具体业务配置为准。

### 8.2 `TranslationMode`

```swift
public enum TranslationMode {
    case offline
    case online
    case auto
    case mix
}
```

说明：

- `offline`：离线翻译。
- `online`：在线翻译。
- `auto`：自动选择。
- `mix`：离线 + 在线混合。

注意：

- 当前 SDK 实现中，`auto` 和 `mix` 会落到在线引擎执行。
- 对外接入时，如果需要明确行为，建议优先使用 `.online` 或 `.offline`。

### 8.3 `EngineType`

```swift
public enum EngineType {
    case offline
    case online
}
```

用于识别当前通道实际使用的引擎类型。

### 8.4 `TmkTranslationPlaybackAudioDataMode`

```swift
public enum TmkTranslationPlaybackAudioDataMode {
    case audioFrameDelegate
    case pullPlaybackAudioFrameRawData
}
```

说明：

- `audioFrameDelegate`
  - 使用音频帧代理方式获取下行音频。
- `pullPlaybackAudioFrameRawData`
  - 使用主动拉取方式获取下行音频。

### 8.5 `TmkTranslationPlaybackAudioPullConfig`

```swift
public struct TmkTranslationPlaybackAudioPullConfig {
    public let intervalMs: Int
    public let lengthInByte: Int?

    public init(intervalMs: Int = 10, lengthInByte: Int? = nil)
}
```

字段说明：

- `intervalMs`
  - 拉取周期，单位毫秒。
  - 默认 `10`。
- `lengthInByte`
  - 每次拉取的字节数。
  - `nil` 表示由 SDK 自动计算。

### 8.6 `TmkTranslationChannelConfig.Builder`

```swift
public final class Builder {
    public init()
    public func setRoom(_ room: TmkTranslationRoom) -> Builder
    public func setMode(_ mode: TranslationMode) -> Builder
    public func setScenario(_ scenario: Scenario) -> Builder
    public func setSourceLang(_ langCode: String) -> Builder
    public func setTargetLang(_ langCode: String) -> Builder
    public func setPCMSampleRate(_ sampleRate: Int) -> Builder
    public func setPCMChannels(_ channels: Int) -> Builder
    public func setPlaybackAudioDataMode(_ mode: TmkTranslationPlaybackAudioDataMode) -> Builder
    public func setPlaybackAudioPullConfig(_ config: TmkTranslationPlaybackAudioPullConfig) -> Builder
    public func setMessageTunnel(_ tunnel: TmkTranslationMessageTunnel) -> Builder
    public func setModelRootDirectory(_ directory: String) -> Builder
    public func build() -> TmkTranslationChannelConfig
}
```

各接口说明：

#### `setRoom(_:)`

- 在线翻译必填。
- 离线翻译不需要设置房间。

#### `setMode(_:)`

- 设置翻译模式，通常使用 `.online` 或 `.offline`。

#### `setScenario(_:)`

- 设置通道场景。
- 收听模式一般传 `.listen`。
- 一对一一般传 `.oneToOne`。

#### `setSourceLang(_:)` / `setTargetLang(_:)`

- 设置源语言和目标语言代码。
- 在线通常使用 BCP-47 代码，例如 `zh-CN`、`en-US`。
- 离线通常使用短码，例如 `zh`、`en`。

#### `setPCMSampleRate(_:)`

- 设置输入 PCM 采样率。
- 当前 SDK 与 Demo 主流程以 `16000` 为准。
- 其他采样率暂未完成完整兼容性验证，正式接入建议优先使用 `16000`。

#### `setPCMChannels(_:)`

- 设置输入 PCM 通道数。
- `1`：单声道。
- `2`：双声道。

#### `setPlaybackAudioDataMode(_:)`

- 设置下行音频获取方式。

#### `setPlaybackAudioPullConfig(_:)`

- 设置播放音频拉取参数。
- 该配置是否生效，取决于当前引擎与音频输出模式；接入时不要将其视为所有场景都必然生效的控制项。

#### `setMessageTunnel(_:)`

- 设置文本消息通道。
- 仅在线翻译生效，离线翻译会忽略该配置。
- 默认使用房间上的 `messageTunnel`。

#### `setModelRootDirectory(_:)`

- 仅离线翻译需要设置。
- 传模型根目录绝对路径。

#### `build()`

- 构建不可变的 `TmkTranslationChannelConfig`。

### 8.7 创建通道接口（在线/离线统一入口）

```swift
public func createTranslationChannel(
    _ config: TmkTranslationChannelConfig,
    callback: @escaping CreateChannelCallback
)

public func createTranslationChannel(
    _ config: TmkTranslationChannelConfig,
    listener: TmkTranslationListener?,
    callback: @escaping CreateChannelCallback
)
```

参数说明：

- `config`
  - 通道配置对象。
- `listener`
  - 可选，启动前预绑定的监听器。
- `callback`
  - 通道创建结果回调。

返回值：

- 无返回值。
- 创建成功后，通过 `callback(.success(TmkTranslationChannel))` 返回通道对象。

说明：

- 在线和离线都通过该接口创建通道。
- SDK 会根据 `config.mode` 选择实际引擎：
  - `mode = .online`：在线引擎
  - `mode = .offline`：离线引擎
- SDK 会在创建成功后自动启动通道。

### 8.8 在线通道创建示例

#### 收听模式

```swift
let config = TmkTranslationChannelConfig.Builder()
    .setRoom(room)
    .setScenario(.listen)
    .setMode(.online)
    .setSourceLang("zh-CN")
    .setTargetLang("en-US")
    .setPCMSampleRate(16_000)
    .setPCMChannels(1)
    .build()

TmkTranslationSDK.shared.createTranslationChannel(config, listener: self) { result in
    switch result {
    case .success(let channel):
        self.channel = channel
    case .failure(let error):
        print(error.message)
    }
}
```

#### 一对一模式

```swift
let config = TmkTranslationChannelConfig.Builder()
    .setRoom(room)
    .setScenario(.oneToOne)
    .setMode(.online)
    .setSourceLang("zh-CN")
    .setTargetLang("en-US")
    .setPCMSampleRate(16_000)
    .setPCMChannels(2)
    .build()

TmkTranslationSDK.shared.createTranslationChannel(config) { result in
    switch result {
    case .success(let channel):
        channel.setTranslationListener(self)
        self.channel = channel
    case .failure(let error):
        print(error.message)
    }
}
```

---

## 9. 离线模型管理

离线翻译并不是“零前置条件即可直接使用”。在正式使用离线翻译前，至少需要满足以下条件：

1. 至少成功调用过一次 `verifyAuth(_:)`。
2. 当前账号已开通离线翻译能力，即 `isOfflineTranslationSupported()` 返回 `true`。
3. 所需离线模型曾下载成功，且本地文件仍然完整可用。

### 9.1 默认离线模型目录

```swift
public func defaultOfflineModelRootDirectory() -> String
public func defaultOfflineModelRootDirectoryURL() -> URL
```

说明：

- 返回 SDK 默认离线模型目录（`Documents/tmkOfflineModel`）。
- 业务方不传 `modelRootDirectory` 时，相关离线接口会使用该目录。

### 9.2 `downloadOfflineModels(...)`

```swift
public func downloadOfflineModels(
    srcLang: String,
    dstLang: String,
    modelRootDirectory: String? = nil,
    scenario: Scenario = .oneToOne,
    needMt: Bool = true,
    needTts: Bool = true,
    listener: TmkOfflineModelDownloadListener?
)
```

参数说明：

- `srcLang`
  - 源语言代码，例如 `zh`。
- `dstLang`
  - 目标语言代码，例如 `en`。
- `modelRootDirectory`
  - 模型根目录。
  - `nil` 时使用默认目录。
- `scenario`
  - `.listen` 或 `.oneToOne`。
- `needMt`
  - 是否下载 MT 模型。
- `needTts`
  - 是否下载 TTS 模型。
- `listener`
  - 下载监听器。

### 9.3 `cancelOfflineModelDownload()`

```swift
public func cancelOfflineModelDownload()
```

说明：

- 取消当前正在进行的离线模型下载。

### 9.4 `getOfflineModelPackageInfos(...)`

```swift
public func getOfflineModelPackageInfos(
    srcLang: String,
    dstLang: String,
    modelRootDirectory: String? = nil,
    scenario: Scenario = .oneToOne,
    needMt: Bool = true,
    needTts: Bool = true
) -> [TmkOfflineModelPackageInfo]
```

说明：

- 获取指定语言对在当前场景下的离线模型包清单与状态。
- 可用于下载前展示包列表，或用于模型状态诊断。

### 9.5 模型就绪检查接口

```swift
public func isOfflineModelReady(
    srcLang: String,
    dstLang: String,
    modelRootDirectory: String? = nil,
    scenario: Scenario = .oneToOne,
    needMt: Bool = true,
    needTts: Bool = true
) -> Bool
```

```swift
public func isAsrModelReady(langCode: String, modelRootDirectory: String? = nil) -> Bool
public func isMtModelReady(srcLang: String, dstLang: String, modelRootDirectory: String? = nil) -> Bool
public func isTtsModelReady(langCode: String, modelRootDirectory: String? = nil) -> Bool
public func isTtsDataReady(modelRootDirectory: String? = nil) -> Bool
```

```swift
public func checkOfflineModelReadyAsync(
    srcLang: String,
    dstLang: String,
    modelRootDirectory: String? = nil,
    scenario: Scenario = .oneToOne,
    needMt: Bool = true,
    needTts: Bool = true,
    callbackQueue: DispatchQueue = .main,
    completion: @escaping OfflineModelReadyCallback
)
```

说明：

- `isOfflineModelReady(...)`
  - 校验当前语言对在指定场景下所需资源是否都已就绪。
- `checkOfflineModelReadyAsync(...)`
  - 异步执行离线模型就绪检查。
  - 推荐在页面初始化或 UI 交互链路中优先使用，避免同步目录扫描导致主线程卡顿。
- 其余接口用于单项模型检查。

### 9.6 离线场景所需模型说明

#### 收听模式 `Scenario.listen`

以 `zh -> en` 为例，通常需要：

- `asr/zh`
- `mt/zh2en`
- `tts/en`
- `tts/espeak-ng-data`

#### 一对一模式 `Scenario.oneToOne`

以 `zh <-> en` 为例，通常需要：

- `asr/zh`
- `asr/en`
- `mt/zh2en`
- `mt/en2zh`
- `tts/zh`
- `tts/en`
- `tts/espeak-ng-data`

### 9.7 离线通道创建示例（统一接口）

#### 离线收听

```swift
let config = TmkTranslationChannelConfig.Builder()
    .setMode(.offline)
    .setScenario(.listen)
    .setSourceLang("zh")
    .setTargetLang("en")
    .setPCMSampleRate(16_000)
    .setPCMChannels(1)
    .setModelRootDirectory(modelRootDirectory)
    .build()

TmkTranslationSDK.shared.createTranslationChannel(config, listener: self) { result in
    switch result {
    case .success(let channel):
        self.channel = channel
    case .failure(let error):
        print(error.message)
    }
}
```

#### 离线一对一

```swift
let config = TmkTranslationChannelConfig.Builder()
    .setMode(.offline)
    .setScenario(.oneToOne)
    .setSourceLang("zh")
    .setTargetLang("en")
    .setPCMSampleRate(16_000)
    .setPCMChannels(2)
    .setModelRootDirectory(modelRootDirectory)
    .build()

TmkTranslationSDK.shared.createTranslationChannel(config, listener: self) { result in
    switch result {
    case .success(let channel):
        self.channel = channel
    case .failure(let error):
        print(error.message)
    }
}
```

---

## 10. 通道对象 `TmkTranslationChannel`

`TmkTranslationChannel` 表示一个正在工作的翻译通道。

### 10.1 `pushStreamAudioData(_:channelCount:extraChunk:)`

```swift
public func pushStreamAudioData(_ data: Data, channelCount: Int, extraChunk: Data? = nil)
```

参数说明：

- `data`
  - 输入 PCM 数据。
- `channelCount`
  - 输入通道数。
  - `1`：单声道。
  - `2`：双声道。
- `extraChunk`
  - 附加透传数据。
  - 一般传 `nil`。

### 10.2 生命周期方法

```swift
public func start()
public func start(completion: @escaping (Result<Void, TmkTranslationError>) -> Void)
public func stop()
public func release()
```

说明：

- `start()` / `start(completion:)`
  - 启动通道。
  - 通过 SDK 创建出来的通道通常已经自动启动，业务方一般不需要再次手动调用。
- `stop()`
  - 停止当前通道。
- `release()`
  - 释放通道资源。
  - 释放后不可再次启动。

### 10.3 状态与能力查询

```swift
public func currentRuntimeState() -> TmkTranslationChannelStateSnapshot
public func getTranslationMode() -> TranslationMode
public func getScenario() -> Scenario
public func getChannelEngineType() -> EngineType
public func setTranslationListener(_ listener: TmkTranslationListener)
```

说明：

- `currentRuntimeState()`
  - 获取当前通道状态快照。
- `getTranslationMode()`
  - 获取创建通道时配置的翻译模式。
- `getScenario()`
  - 获取创建通道时配置的场景。
- `getChannelEngineType()`
  - 获取当前通道实际使用的引擎类型。
- `setTranslationListener(_:)`
  - 动态设置监听器。

---

## 11. 监听器与回调数据

## 11.1 `TmkTranslationListener`

```swift
public protocol TmkTranslationListener: AnyObject {
    func onRecognized(from engine: AbstractChannelEngine, result: TmkResult<String>, isFinal: Bool)
    func onTranslate(from engine: AbstractChannelEngine, result: TmkResult<String>, isFinal: Bool)
    func onAudioDataReceive(from engine: AbstractChannelEngine, result: TmkResult<String>, data: Data, channelCount: Int)
    func onError(_ error: TmkTranslationError)
    func onError(code: Int, message: String)
    func onEvent(name: String, args: Any?)
    func onStateChanged(from engine: AbstractChannelEngine, snapshot: TmkTranslationChannelStateSnapshot)
}
```

回调线程：

- `TmkTranslationListener` 的所有回调都会在主线程回调。

各回调说明：

### `onRecognized(...)`

- 识别结果回调。
- `result.data`：识别文本。
- `isFinal` 可能取值：
  - `false`：增量识别结果，后续还可能继续回调。
  - `true`：本段识别最终结果。
- `result.isLast`：当前结果对象中的结束标记，通常与 `isFinal` 含义保持一致。
- `result.srcCode` / `result.dstCode`：当前通道的源语言与目标语言代码。
- `result.extraData` 字段与可能取值（按当前 SDK 实现）：

| key | 类型 | 可能取值/说明 | 出现场景 |
| --- | --- | --- | --- |
| `trace_id` | `String` | 链路追踪 ID；未启用 trace 时可能不存在 | 在线/离线 |
| `bubble_id` | `String` | 文本气泡 ID；离线通常形如 `offline_<sessionId>` | 在线/离线 |
| `channel` | `String` | 常见：`left`、`right`、`1`（离线收听） | 在线/离线 |
| `kind` | `String` | `origin` | 离线 |
| `state` | `String` | `partial`、`completed` | 离线 |
| `text` | `String` | 当前识别文本（通常与 `result.data` 一致） | 离线 |

注意：`extraData` 字段按事件和模式动态出现，不保证全部存在。

### `onTranslate(...)`

- 翻译结果回调。
- `result.data`：翻译文本。
- `isFinal` 可能取值：
  - `false`：增量翻译结果。
  - `true`：本段翻译最终结果。
- `result.extraData` 字段与可能取值（按当前 SDK 实现）：

| key | 类型 | 可能取值/说明 | 出现场景 |
| --- | --- | --- | --- |
| `trace_id` | `String` | 链路追踪 ID；未启用 trace 时可能不存在 | 在线/离线 |
| `bubble_id` | `String` | 文本气泡 ID；离线通常形如 `offline_<sessionId>` | 在线/离线 |
| `channel` | `String` | 常见：`left`、`right`、`1`（离线收听） | 在线/离线 |
| `kind` | `String` | `translation` | 离线 |
| `state` | `String` | `partial`、`completed` | 离线 |
| `text` | `String` | 当前翻译文本（通常与 `result.data` 一致） | 离线 |

注意：`extraData` 字段按事件和模式动态出现，不保证全部存在。

### `onAudioDataReceive(...)`

- 翻译后的 PCM 音频回调。
- `data`：原始 PCM16LE 音频数据。
- `channelCount` 可能取值：
  - `1`：单声道。
  - `2`：双声道。
- `result.data` 当前通常是描述性文本，不建议业务方依赖其固定内容。
- `result.extraData` 字段与可能取值（按当前 SDK 实现）：

| key | 类型 | 可能取值/说明 | 出现场景 |
| --- | --- | --- | --- |
| `uid` | `UInt` | 音频来源 UID | 在线 |
| `trace_id` | `String` | 链路追踪 ID；未启用 trace 时可能不存在 | 离线 |
| `bubble_id` | `String` | 文本气泡 ID；离线通常形如 `offline_<sessionId>` | 离线 |
| `channel` | `String` | `1`（离线收听）或 `left`/`right`（离线一对一） | 离线 |

### `onError(_:)`

- SDK 统一错误回调。
- `error.code`：统一错误码。
- `error.category` 常见取值：`caller`、`network`、`rtcRtm`、`audio`、`state`、`internal`。
- `error.message`：对外可读的错误描述。

### `onError(code:message:)`

- 兼容旧接口的错误回调。
- 默认实现会由 `onError(_:)` 自动桥接。

### `onEvent(name:args:)`

- 通用事件回调。
- `name` 为事件名。
- `args` 通常为 `TmkResult<String>`，也可能为 `nil`。
- 当 `args` 为 `TmkResult<String>` 时，可通过 `result.extraData` 获取事件扩展字段。

常见在线事件：

| 事件名 | 含义 | `args` 常见内容 |
| --- | --- | --- |
| `online_stream_message_parsed` | 在线识别/翻译流消息解析完成 | `TmkResult<String>` |
| `online_audio_metadata` | 在线音频链路元数据事件 | `TmkResult<String>` 或 `nil` |
| `online_recognition_failure` | 在线识别失败 | `TmkResult<String>` 或 `nil` |
| `online_notification` | 在线通知事件 | `TmkResult<String>` 或 `nil` |
| `online_tts_state` | 在线 TTS 状态变化 | `TmkResult<String>` 或 `nil` |

在线事件 `result.extraData` 字段与可能取值：

| key | 类型 | 可能取值/说明 |
| --- | --- | --- |
| `uid` | `UInt` | 远端用户 UID |
| `stream_id` | `Int` | Agora 流 ID |
| `event` | `String` | `translate_speech_to_speech`、`notification`、`recognition_failure`、`tts_playback_state` 或其他服务端事件名 |
| `event_type` | `String` | `translateSpeechToSpeech`、`notification`、`recognitionFailure`、`ttsPlaybackState`、`unknown(...)` |
| `kind` | `String` | 常见：`origin`、`translation` |
| `trace_id` | `String` | 链路追踪 ID |
| `channel` | `String` | 常见：`left`、`right` |
| `locale` | `String` | 语言代码，如 `zh-CN`、`en-US` |
| `text` | `String` | 事件文本内容 |
| `state` | `String` | 常见：`partial`、`completed`、`failed`、`started` |
| `is_end` | `Bool` | `true` / `false` |
| `bubble_id` | `String` | 文本气泡 ID |
| `metadata_size` | `Int` | metadata 字节数（`online_audio_metadata`） |
| `payload_size` | `Int` | 消息/metadata 字节数 |
| `tx_quality` | `Int` | 上行网络质量（Agora 枚举值） |
| `rx_quality` | `Int` | 下行网络质量（Agora 枚举值） |
| `audio_loss_rate` | `Int` | 音频丢包率（百分比整数） |

常见离线事件：

| 事件名 | 含义 | `args` 常见内容 |
| --- | --- | --- |
| `offline_stream_message_parsed` | 离线识别/翻译事件 | `TmkResult<String>` |
| `offline_audio_metadata` | 离线音频链路元数据事件 | `TmkResult<String>` 或 `nil` |
| `offline_recognition_failure` | 离线识别失败 | `TmkResult<String>` 或 `nil` |
| `offline_notification` | 离线通知事件 | `TmkResult<String>` 或 `nil` |
| `offline_tts_state` | 离线 TTS 状态变化 | `TmkResult<String>` 或 `nil` |

离线事件 `result.extraData` 字段与可能取值：

| key | 类型 | 可能取值/说明 |
| --- | --- | --- |
| `trace_id` | `String` | 链路追踪 ID；仅在 Demo 侧发送 trace 时存在 |
| `bubble_id` | `String` | 文本气泡 ID，常见 `offline_<sessionId>` |
| `channel` | `String` | 收听：`1`；一对一：`left` / `right` |
| `event` | `String` | `translate_speech_to_speech`、`recognition_failure`、`notification`、`tts_playback_state` |
| `kind` | `String` | `origin`、`translation`（`offline_stream_message_parsed`） |
| `state` | `String` | `partial`、`completed`、`failed`、`started` |
| `text` | `String` | 事件文本或错误文本 |
| `locale` | `String` | 语言代码（origin=源语言，translation=目标语言） |
| `stage` | `String` | `asr`、`translation`、`tts`（失败通知事件） |
| `uid` | `UInt` | 音频 metadata 对应 UID（`offline_audio_metadata`） |
| `metadata_size` | `Int` | metadata 字节数 |
| `payload_size` | `Int` | payload 字节数 |

### `onStateChanged(...)`

- 通道状态变化回调。
- 推荐业务方监听该回调，用于展示“启动中 / 运行中 / 重连中 / 失败”等状态。
- `snapshot.state` 全量取值见下文 `TmkTranslationChannelState`。
- `snapshot.reason` 全量取值见下文 `TmkTranslationChannelStateReason`。
- `snapshot.code`：当状态变化由错误触发时，可能包含错误码；否则为 `nil`。
- `snapshot.isRecoverable`：`true` 表示 SDK 仍可能自动恢复，`false` 表示通常需要业务方介入。

示例：

```swift
final class TranslationHandler: TmkTranslationListener {
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
        print("audio bytes=\(data.count), channelCount=\(channelCount)")
    }

    func onError(_ error: TmkTranslationError) {
        print("error=\(error.code) \(error.message)")
    }

    func onEvent(name: String, args: Any?) {
        print("event=\(name)")
    }
}
```

## 11.2 `TmkResult<T>`

```swift
public struct TmkResult<T> {
    public let sessionId: Int
    public let data: T
    public let srcCode: String
    public let dstCode: String
    public let isLast: Bool
    public let extraData: [String: Any]
}
```

字段说明：

- `sessionId`
  - 会话 ID。
  - 在线场景下一般对应 Agora uid 或会话维度标识。
- `data`
  - 结果主体。
  - 文本结果里通常是 `String`。
- `srcCode`
  - 源语言代码。
- `dstCode`
  - 目标语言代码。
- `isLast`
  - 是否是最后一条结果。
- `extraData`
  - 附加信息字典。

注意：

- `extraData` 属于兼容型扩展字段。
- 不同模式和不同事件的字段可能不同。
- 如无明确依赖，请不要强依赖某个未文档化 key；建议仅使用本节 `11.1` 中已列字段。

## 11.3 通道状态模型

### `TmkTranslationChannelState`

```swift
public enum TmkTranslationChannelState: String {
    case idle
    case starting
    case running
    case reconnecting
    case degraded
    case stopping
    case stopped
    case failed
}
```

常见取值说明：

| 值 | 含义 |
| --- | --- |
| `idle` | 初始状态，尚未启动 |
| `starting` | 启动中 |
| `running` | 运行中 |
| `reconnecting` | 重连中 |
| `degraded` | 已降级运行，通常仍可继续工作 |
| `stopping` | 停止中 |
| `stopped` | 已停止 |
| `failed` | 已失败，通常需要业务方介入 |

### `TmkTranslationChannelStateReason`

```swift
public enum TmkTranslationChannelStateReason: String {
    case none
    case startRequested
    case started
    case stopRequested
    case stopped
    case networkUnavailable
    case networkRestored
    case rtcConnecting
    case rtcConnected
    case rtcInterrupted
    case rtcLost
    case rtcKeepAliveTimeout
    case rtcTokenRequested
    case rtcTokenWillExpire
    case sessionExpired
    case invalidConfiguration
    case permissionDenied
    case bannedByServer
    case serviceRejected
    case messageChannelFailure
    case engineError
}
```

常见取值说明：

| 值 | 含义 |
| --- | --- |
| `none` | 无特殊原因 |
| `startRequested` | 已收到启动请求 |
| `started` | 启动完成 |
| `stopRequested` | 已收到停止请求 |
| `stopped` | 已停止 |
| `networkUnavailable` | 网络不可用 |
| `networkRestored` | 网络已恢复 |
| `rtcConnecting` | 在线链路连接中 |
| `rtcConnected` | 在线链路已连接 |
| `rtcInterrupted` | 在线链路中断 |
| `rtcLost` | 在线链路丢失 |
| `rtcKeepAliveTimeout` | 在线保活超时 |
| `rtcTokenRequested` | 正在请求 RTC token |
| `rtcTokenWillExpire` | RTC token 即将过期 |
| `sessionExpired` | 当前会话已过期 |
| `invalidConfiguration` | 配置无效 |
| `permissionDenied` | 权限不足 |
| `bannedByServer` | 被服务端禁用 |
| `serviceRejected` | 服务端拒绝请求 |
| `messageChannelFailure` | 文本消息通道异常 |
| `engineError` | 底层引擎异常 |

### `TmkTranslationChannelStateSnapshot`

```swift
public struct TmkTranslationChannelStateSnapshot {
    public let state: TmkTranslationChannelState
    public let reason: TmkTranslationChannelStateReason
    public let code: Int?
    public let message: String
    public let isRecoverable: Bool
    public let updatedAt: Date
}
```

字段说明：

- `state`
  - 当前状态。
- `reason`
  - 状态变化原因。
- `code`
  - 关联错误码，可能为空。
- `message`
  - 补充说明文本。
- `isRecoverable`
  - 是否可恢复。
- `updatedAt`
  - 更新时间。

---

## 12. 错误模型

### 12.1 `TmkTranslationErrorCategory`

```swift
public enum TmkTranslationErrorCategory: String {
    case caller
    case network
    case rtcRtm
    case audio
    case state
    case `internal`
}
```

### 12.2 `TmkTranslationError`

```swift
public enum TmkTranslationError: Error, LocalizedError
```

常用公开属性：

- `code: Int`
  - SDK 统一错误码。
- `constantName: String`
  - 错误码常量名。
- `message: String`
  - 对外可读错误文案。
- `category: TmkTranslationErrorCategory`
  - 错误分类。
- `chineseDescription: String`
  - 中文说明。
- `englishDescription: String`
  - 英文说明。
- `underlyingError: Error?`
  - 原始底层错误。
- `actualErrorCode: Int?`
  - 实际底层错误码。
- `actualErrorMessage: String?`
  - 实际底层错误信息。
- `actualErrorDomain: String?`
  - 实际底层错误域。

示例：

```swift
func onError(_ error: TmkTranslationError) {
    print(error.code)
    print(error.category.rawValue)
    print(error.message)
    print(error.actualErrorMessage ?? "-")
}
```

### 12.3 离线错误码细化规则

离线翻译在底层失败时，会结合失败阶段细化为统一错误码：

| 失败阶段 | 统一错误码 | 常量 |
| --- | --- | --- |
| `tts` | `2001109` | `TTS_SYNTHESIS_ERROR` |
| `translation` | `2001110` | `TRANSLATION_ERROR` |
| `asr` | `2001110` | `TRANSLATION_ERROR` |

补充说明：

- 当底层错误已经是明确错误（如 `INVALID_CONFIGURATION`、`INVALID_STATE`、`ENGINE_INITIALIZATION_FAILED`）时，不会被阶段规则覆盖。
- `error.actualErrorCode` / `error.actualErrorMessage` 会继续保留底层离线组件的原始错误信息，便于排障。

### 12.4 统一错误码对齐说明

- SDK 统一错误码表请见文档末尾一级目录：`20. SDK 统一错误码表（与 iOS 代码同步）`。
- `error.code` 对应统一错误码表。
- `error.actualErrorCode` 可能是底层组件错误码（例如离线组件 `2004xxx`），用于排障。

---

## 13. 离线模型下载监听器

### 13.1 `TmkOfflineModelPackageState`

```swift
public enum TmkOfflineModelPackageState: String {
    case ready
    case needsDownload
    case needsUpdate
    case resumable
    case downloading
    case unzipping
    case failed
    case cancelled
}
```

取值说明：

| 值 | 含义 |
| --- | --- |
| `ready` | 已准备完成 |
| `needsDownload` | 尚未下载，需要下载 |
| `needsUpdate` | 本地版本过旧，需要更新 |
| `resumable` | 可继续下载 |
| `downloading` | 下载中 |
| `unzipping` | 解压中 |
| `failed` | 处理失败 |
| `cancelled` | 已取消 |

### 13.2 `TmkOfflineModelPackageInfo`

```swift
public struct TmkOfflineModelPackageInfo {
    public let packageKey: String
    public let type: String
    public let name: String
    public let state: TmkOfflineModelPackageState
    public let index: Int
    public let total: Int
    public let downloadedBytes: Int64
    public let totalBytes: Int64
    public let unzipProgress: Double
    public let localDirectory: String
}
```

字段说明：

- `packageKey`
  - 资源包键，例如 `asr/zh`。
- `type`
  - 包类型，例如 `asr`、`mt`、`tts`。
- `name`
  - 包名称，例如 `zh`、`zh2en`。
- `state`
  - 当前资源包状态。
- `index` / `total`
  - 当前批次中的序号和总数。
- `downloadedBytes` / `totalBytes`
  - 下载进度。
- `unzipProgress`
  - 解压进度，范围 `0.0 ~ 1.0`。
- `localDirectory`
  - 本地目录。

### 13.3 `TmkOfflineModelDownloadListener`

```swift
public protocol TmkOfflineModelDownloadListener: AnyObject {
    func onOfflineModelEvent(name: String, args: Any?)
    func onOfflineModelDownloadProgress(fileName: String, index: Int, total: Int, downloaded: Int64, fileTotal: Int64)
    func onOfflineModelUnzipProgress(fileName: String, progress: Double)
    func onOfflineModelReady()
    func onOfflineModelPackageInfosChanged(_ packages: [TmkOfflineModelPackageInfo])
    func onOfflineModelError(_ error: TmkTranslationError)
}
```

回调线程：

- `TmkOfflineModelDownloadListener` 的所有回调都会在主线程回调。

各回调说明：

- `onOfflineModelEvent(name:args:)`
  - 下载过程中的通用事件回调。
  - `name` 为事件名。
  - `args` 可能为 `nil`，也可能为简单说明对象。业务方不应强依赖其具体结构。

- `onOfflineModelDownloadProgress(fileName:index:total:downloaded:fileTotal:)`
  - 下载进度回调。
  - `fileName`：当前资源包名称。
  - `index`：当前资源包在本次下载批次中的序号，通常从 `1` 开始。
  - `total`：当前批次总包数。
  - `downloaded`：当前包已下载字节数。
  - `fileTotal`：当前包总字节数；当总大小未知时，可能为 `-1`。

- `onOfflineModelUnzipProgress(fileName:progress:)`
  - 解压进度回调。
  - `progress` 范围为 `0.0 ~ 1.0`。

- `onOfflineModelReady()`
  - 当前批次所需模型均已准备完成。

- `onOfflineModelPackageInfosChanged(_:)`
  - 整批资源包状态变化回调。
  - `packages` 中每个 `TmkOfflineModelPackageInfo.state` 可能取值：
    - `ready`：已就绪
    - `needsDownload`：需要下载
    - `needsUpdate`：需要更新
    - `resumable`：可继续下载
    - `downloading`：下载中
    - `unzipping`：解压中
    - `failed`：失败
    - `cancelled`：已取消

- `onOfflineModelError(_:)`
  - 下载或解压过程中的统一错误回调。

---

## 14. 诊断能力

### 14.1 `getDiagnosisDirectoryURL()`

```swift
public func getDiagnosisDirectoryURL() -> URL?
```

返回值：

- 诊断目录 URL。
- 如果当前没有诊断目录，返回 `nil`。

说明：

- 只有在 `setDiagnosisEnabled(true)` 后，SDK 才会产生诊断文件。
- 目录中可能包含日志、诊断音频等排障信息。
- 分享或上传前，建议由业务方确认数据合规。

示例：

```swift
guard let diagnosisURL = TmkTranslationSDK.shared.getDiagnosisDirectoryURL() else {
    return
}
print(diagnosisURL)
```

---

## 15. PCM 工具

`TmkTranslationPCMTools` 提供常用 PCM 工具方法：

```swift
public enum TmkTranslationPCMTools {
    public static func mixStereo16LE(left: Data, right: Data) -> Data?
    public static func mixMonoToStereo16LE(mono: Data, isLeft: Bool) -> Data?
    public static func splitStereoInterleaved16LE(_ stereo: Data) -> (left: Data, right: Data)?
    public static func pcm16LEToFloat(_ data: Data) -> [Float]
    public static func floatToPCM16LE(_ samples: [Float]) -> Data
}
```

用途说明：

- `mixStereo16LE(left:right:)`
  - 将左右单声道 PCM 合成为立体声交错 PCM。
- `mixMonoToStereo16LE(mono:isLeft:)`
  - 把单声道复制到左或右声道，生成立体声。
- `splitStereoInterleaved16LE(_:)`
  - 将立体声交错 PCM 拆成左右单声道。
- `pcm16LEToFloat(_:)`
  - 16-bit PCM 转浮点数组。
- `floatToPCM16LE(_:)`
  - 浮点数组转 16-bit PCM。

---

## 16. 可取消请求句柄

### 16.1 `TmkSDKCancellable`

```swift
public protocol TmkSDKCancellable {
    func cancel()
}
```

说明：

- 用于取消未完成的异步请求，例如语言列表请求、房间关闭请求等。

### 16.2 `TmkAnySDKCancellable`

```swift
public final class TmkAnySDKCancellable: TmkSDKCancellable {
    public init(onCancel: @escaping () -> Void)
    public func cancel()
}
```

一般业务方不需要主动创建，通常只需要持有 SDK 返回的 `TmkSDKCancellable?` 即可。

---

## 17. 资源释放与生命周期

### `releaseChannel()`

```swift
public func releaseChannel()
```

说明：

- 释放当前翻译通道与当前会话相关资源。
- 不会清空 `sdkInit` 的全局配置，也不会清空鉴权状态。
- 释放后可以重新创建新通道。

### `destroy()`

```swift
public func destroy()
```

说明：

- 释放全局资源。
- 会释放当前通道、清空鉴权状态、清空全局配置、关闭诊断与网络监听。
- 调用后如果要继续使用 SDK，必须重新执行 `sdkInit(_:)`。

建议：

- 页面级退出当前翻译会话时，优先使用 `releaseChannel()`。
- 应用彻底退出 SDK 使用场景时，再调用 `destroy()`。

---

## 18. 最小接入示例

### 18.1 在线收听最小示例

```swift
import TmkTranslationSDK

final class OnlineListenHandler: TmkTranslationListener {
    func onRecognized(from engine: AbstractChannelEngine, result: TmkResult<String>, isFinal: Bool) {
        print("识别: \(result.data)")
    }

    func onTranslate(from engine: AbstractChannelEngine, result: TmkResult<String>, isFinal: Bool) {
        print("翻译: \(result.data)")
    }

    func onAudioDataReceive(from engine: AbstractChannelEngine,
                            result: TmkResult<String>,
                            data: Data,
                            channelCount: Int) {
        print("音频字节数: \(data.count)")
    }

    func onError(_ error: TmkTranslationError) {
        print(error.message)
    }
}

let handler = OnlineListenHandler()

let config = TmkTranslationGlobalConfig.Builder()
    .setAuth(appId: "your_app_id", secret: "your_app_secret")
    .setOnlineAuthContext(tenantId: "timekettle", externalUserId: "u001", installId: nil)
    .setNetworkEnvironment(.test)
    .build()

TmkTranslationSDK.shared.sdkInit(config)
TmkTranslationSDK.shared.verifyAuth { result in
    switch result {
    case .success:
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
                let channelConfig = TmkTranslationChannelConfig.Builder()
                    .setRoom(room)
                    .setScenario(.listen)
                    .setMode(.online)
                    .setSourceLang("zh-CN")
                    .setTargetLang("en-US")
                    .setPCMSampleRate(16_000)
                    .setPCMChannels(1)
                    .build()

                TmkTranslationSDK.shared.createTranslationChannel(channelConfig, listener: handler) { result in
                    switch result {
                    case .success(let channel):
                        // 业务侧持续推送 PCM 数据
                        channel.pushStreamAudioData(pcmData, channelCount: 1)
                    case .failure(let error):
                        print(error.message)
                    }
                }
            case .failure(let error):
                print(error.message)
            }
        }
        _ = room
    case .failure(let error):
        print(error.message)
    }
}
```

### 18.2 离线收听最小示例

```swift
import TmkTranslationSDK

let modelRootDirectory = "/path/to/offline_models"

TmkTranslationSDK.shared.verifyAuth { result in
    switch result {
    case .success:
        guard TmkTranslationSDK.shared.isOfflineTranslationSupported() else {
            print("当前账号不支持离线翻译")
            return
        }

        guard TmkTranslationSDK.shared.isOfflineModelReady(
            srcLang: "zh",
            dstLang: "en",
            modelRootDirectory: modelRootDirectory,
            scenario: .listen,
            needMt: true,
            needTts: true
        ) else {
            print("离线模型未就绪")
            return
        }

        let channelConfig = TmkTranslationChannelConfig.Builder()
            .setMode(.offline)
            .setScenario(.listen)
            .setSourceLang("zh")
            .setTargetLang("en")
            .setPCMSampleRate(16_000)
            .setPCMChannels(1)
            .setModelRootDirectory(modelRootDirectory)
            .build()

        TmkTranslationSDK.shared.createTranslationChannel(channelConfig, listener: handler) { result in
            switch result {
            case .success(let channel):
                channel.pushStreamAudioData(pcmData, channelCount: 1)
            case .failure(let error):
                print(error.message)
            }
        }
    case .failure(let error):
        print(error.message)
    }
}
```

### 18.3 一对一模式与收听模式的区别

| 项目 | 收听模式 | 一对一模式 |
| --- | --- | --- |
| `Scenario` | `.listen` | `.oneToOne` |
| `pcmChannels` | `1` | `2` |
| 在线是否建房 | 是 | 是 |
| 离线是否建房 | 否 | 否 |

---

## 19. 常见问题

### 19.1 为什么在线能力需要先调用 `verifyAuth(_:)`？

在线翻译、在线建房与在线建通道都依赖鉴权成功后得到的业务 token。在线语言列表是例外：完成 `sdkInit(_:)` 后即可请求，不依赖 `verifyAuth(_:)`。

### 19.2 为什么离线翻译也建议先调用 `verifyAuth(_:)`？

离线翻译并不是零前置条件直接可用。SDK 在 `verifyAuth(_:)` 中会先完成在线鉴权，并在在线鉴权成功后继续尝试离线鉴权，用于确认当前账号是否开通离线翻译能力，并获取离线能力所需的鉴权信息。

### 19.3 为什么离线模型下载成功过，之后又可能不能使用？

常见原因包括：

- 当前账号已不具备离线能力
- 本地模型目录被删除或不完整
- 模型根目录变更
- 本次创建通道时所需语言对或场景与已下载模型不匹配

建议在创建离线通道前先调用 `isOfflineModelReady(...)` 检查。

### 19.4 为什么在线和离线的语言 code 不完全一样？

在线语言通常使用更完整的 locale 代码，例如 `zh-CN`、`en-US`；离线语言通常使用短码，例如 `zh`、`en`。接入时请始终使用对应语言列表接口返回的实际 code。

### 19.5 为什么当前建议使用 `16000` 采样率？

当前 SDK、Demo 和自动化测试主流程都以 `16000 Hz` 为准。其他采样率暂未完成完整兼容性验证，正式接入建议优先使用 `16000`。

### 19.6 为什么离线一对一模式需要双声道输入？

一对一模式会把左右声道视为两路独立输入：

- 左声道：一侧说话人
- 右声道：另一侧说话人

因此一对一模式应设置 `pcmChannels = 2`，并输入正确的双声道 PCM。

### 19.7 为什么 `onRecognized(...)` 和 `onTranslate(...)` 会多次回调？

这两个回调都支持增量结果：

- `isFinal == false`：中间过程结果
- `isFinal == true`：本段最终结果

业务方应以 `isFinal` 或 `result.isLast` 判断当前结果是否结束。

### 19.8 `releaseChannel()` 和 `destroy()` 有什么区别？

- `releaseChannel()`：只释放当前翻译会话相关资源。下次创建通道前建议先调用。
- `destroy()`：释放 SDK 全局资源。调用后若要继续使用，必须重新 `sdkInit(_:)`，并根据业务重新鉴权。

### 19.9 `auto` / `mix` 可以直接用于生产吗？

当前可以传入，但实际仍会落到在线引擎执行。如果你需要明确行为，建议直接使用 `.online` 或 `.offline`。

### 19.10 `TmkTranslationMessageTunnel` 离线可以用吗？

不可以。`TmkTranslationMessageTunnel` 仅在线翻译使用，离线翻译会忽略该配置。

### 19.11 `isOfflineTranslationSupported()` 返回 `false` 怎么办？

说明当前账号或当前鉴权上下文不支持离线翻译。即使 `verifyAuth(_:)` 已成功，只要离线鉴权未成功，当前接口仍可能返回 `false`。此时不能创建可用的离线翻译通道。请先确认：

- 已成功调用 `verifyAuth(_:)`
- 当前环境配置正确
- 账号已开通离线能力

### 19.12 为什么切换新房间或新通道前建议先释放旧资源？

当前 SDK 使用时建议遵循单房间、单通道模型。创建新的翻译会话前，建议先关闭旧房间并释放旧通道资源，避免旧资源仍占用网络、音频或状态机上下文。

---

## 20. SDK 统一错误码表（与 iOS 代码同步）

以下错误码来自 `TmkSDKErrorCode`，与当前 iOS SDK 实现保持一致：

| code | constantName | category | 说明 |
| --- | --- | --- | --- |
| `2001101` | `SDK_NOT_INITIALIZED` | `state` | SDK 未初始化，必须先调用 `sdkInit` |
| `2001102` | `AUTHENTICATION_FAILED` | `caller` | 认证失败，无法获取或校验业务鉴权信息 |
| `2001103` | `ROOM_CREATION_FAILED` | `network` | 房间创建失败 |
| `2001104` | `CHANNEL_CREATION_FAILED` | `rtcRtm` | 通道创建失败 |
| `2001105` | `ENGINE_NOT_SUPPORTED` | `rtcRtm` | 当前请求的引擎能力不受支持 |
| `2001106` | `INVALID_CONFIGURATION` | `caller` | 配置无效 |
| `2001107` | `NETWORK_UNAVAILABLE` | `network` | 网络不可用 |
| `2001108` | `AUDIO_PROCESSING_ERROR` | `audio` | 音频处理错误 |
| `2001109` | `TTS_SYNTHESIS_ERROR` | `rtcRtm` | 语音合成错误 |
| `2001110` | `TRANSLATION_ERROR` | `rtcRtm` | 翻译流程错误 |
| `2001111` | `SESSION_EXPIRED` | `network` | 会话已过期 |
| `2001112` | `QUOTA_EXCEEDED` | `network` | 服务配额超限 |
| `2001113` | `INVALID_LANGUAGE_CODE` | `caller` | 语言代码无效 |
| `2001114` | `ENGINE_INITIALIZATION_FAILED` | `rtcRtm` | 引擎初始化失败 |
| `2001115` | `BUFFER_OVERFLOW` | `audio` | 缓冲区溢出 |
| `2001116` | `THREAD_INTERRUPTED` | `internal` | 工作线程被中断 |
| `2001117` | `OFFLINE_MODEL_NOT_READY` | `caller` | 离线模型未就绪 |
| `2001999` | `UNKNOWN_ERROR` | `internal` | 未知错误 |
| `2002001` | `NETWORK_INVALID_URL` | `caller` | 网络请求地址无效 |
| `2002002` | `NETWORK_TRANSPORT_ERROR` | `network` | 网络传输失败 |
| `2002003` | `NETWORK_HTTP_STATUS_ERROR` | `network` | 服务端返回非 2xx HTTP 状态码 |
| `2002004` | `NETWORK_RESPONSE_DECODING_ERROR` | `network` | 服务端响应解析失败 |
| `2002005` | `NETWORK_BUSINESS_ERROR` | `network` | 服务端返回业务错误码 |
| `2002006` | `REQUEST_CANCELLED` | `network` | 请求已取消 |
| `2003002` | `INVALID_STATE` | `state` | 当前状态不允许执行该操作 |
| `2003003` | `DEPENDENCY_UNAVAILABLE` | `rtcRtm` | 依赖库不可用 |
| `2003004` | `RTC_OPERATION_FAILED` | `rtcRtm` | RTC/RTM 操作失败 |
| `2003005` | `MESSAGE_DECODING_FAILED` | `rtcRtm` | 消息解码失败 |
| `2003006` | `AUDIO_CHANNEL_CREATION_FAILED` | `audio` | 音频通道创建失败 |
| `2003007` | `TRACK_EVENT_NOT_CONFIGURED` | `internal` | 埋点组件尚未配置 |
| `2003008` | `TRACK_EVENT_INVALID_EVENT_NAME` | `caller` | 埋点事件名为空或非法 |

补充说明：

- `error.code` 对应上表统一错误码。
- `error.actualErrorCode` 可能是底层组件错误码（例如离线组件 `2004xxx`），用于排障。

---

## 21. 版本信息

当前 SDK 代码版本：`TmkTranslationSDK v1.0.0`
