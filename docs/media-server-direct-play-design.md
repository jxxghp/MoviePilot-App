# MoviePilot 客户端优先直连媒体服务器、不可达自动回退后台中转方案

> 适用范围：`MoviePilot`（后端 `v3`）、`MoviePilot-App`（Rust 共享核心、iOS / Android / HarmonyOS NEXT 原生端 `v2`）
> 前置能力：已落地的统一实时播放会话同步与每用户媒体服务器账号绑定（见 `docs/playback-progress-sync-design.md`）

---

## 1. 背景与目标

当前从 MoviePilot App 播放媒体服务器（Emby / Jellyfin / Plex 等）中的非 STRM 音视频时，所有媒体字节流都必须经过：

`客户端 -> MoviePilot 后台 (/api/v1/mediaserver/stream) -> 媒体服务器`

这种纯中转架构在远程外网隔离场景下非常稳健，但在以下高频场景存在明显瓶颈：
1. **家庭局域网直连浪费带宽与资源**：手机/平板与 NAS/Emby 在同一局域网，却绕经 MoviePilot Python 进程转发 4K HDR/原盘高码率（50~100 Mbps）流，造成双重流量、额外延迟和服务端 CPU/连接压力。
2. **外网公网折返**：当媒体服务器已配置独立外网域名 (`play_host`) 或 Emby 302 网盘反代时，经过 MP 二次代理会白白消耗服务器出口带宽，无法发挥客户端直连或 302 直链满速优势。

### 设计目标
1. **控制面与数据面分离**：
   - **控制面继续走 MoviePilot 后台**：详情查询、`stream-info` 协商、`PlaySessionId` 生成、播放进度心跳（`started`/`playing`/`paused`/`stopped`）与离线补报，保证多端策略一致且流量极小。
   - **数据面优先由客户端直连媒体服务器**：自动识别可用直连路由（STRM 直链 > 局域网直连 > 外网直连），不可达或起播失败时自动无缝回退至 MoviePilot 后台中转（`mp_proxy`）。
2. **严格安全边界（零管理员密钥泄露）**：
   - **严禁向任何客户端下发媒体服务器全局管理员 API Key / 全局账号密码**。
   - 仅当当前登录用户已通过 `account-bindings` 绑定其**本人个人令牌**（Emby/Jellyfin 个人 `AccessToken`、Plex 个人 `X-Plex-Token`）时，才为其签发直连路由；未绑定用户保持走 `mp_proxy`（STRM 无凭据直链除外）。
   - 直连令牌一律通过 HTTP `headers` 携带（**不拼入 URL 查询串**），且仅在严格同源（scheme + host + port）请求时附加；遇到跨源 302 重定向（例如跳转至网盘 CDN）时自动剥离认证头。
3. **零感知首帧延迟**：
   - 通过轻量无认证 Ping（`600~700ms` 超时并发探测）+ 按 `(server, networkEpoch)` 5 分钟缓存 + 系统切网自动失效机制，二次起播 0ms 命中路由。
   - 起播阶段如遇证书/403/网络闪断，自动按 `fallback` 顺序无缝降级到下一条路由直至 `mp_proxy`。

---

## 2. 媒体服务器分级直连策略

| 服务器类型 | 直连前置条件 | 凭据传递方式 | 轻量探测端点 (`probe_url`) | 未满足条件时策略 |
| --- | --- | --- | --- | --- |
| **任意服务器（STRM 条目）** | 存在无内嵌凭据的 HTTP(S) `strm_url` 且开启「STRM 直链播放」 | 无凭据或 STRM 安全头 | 直接尝试，失败回退 | 自动降级下一条路由 / `mp_proxy` |
| **Emby** | 当前用户存在有效个人绑定令牌 (`valid_cred.token`) | Header：`X-Emby-Token`、`X-Emby-Authorization` | `{base}/emby/System/Ping` | 走 `mp_proxy` |
| **Jellyfin** | 当前用户存在有效个人绑定令牌 (`valid_cred.token`) | Header：`X-Emby-Token`、`Authorization` | `{base}/System/Ping` | 走 `mp_proxy` |
| **Plex** | 当前用户存在有效个人绑定令牌 (`valid_cred.token`) | Header：`X-Plex-Token`、`X-Plex-Client-Identifier` 等 | `{base}/identity` | 走 `mp_proxy` |
| **Navidrome** | 音乐码率小（0.3~3 Mbps）且 Subsonic 多为全局账号 | — | — | 默认走 `mp_proxy` |
| **极空间 / 绿联 / 飞牛** | 私有会话/Cookie 强依赖后台代理 | — | — | 默认走 `mp_proxy`（若条目本身为 STRM 则走 STRM 直链） |

> **Web 浏览器说明**：HTTPS 浏览器环境存在 Mixed Content（阻止加载 `http://192.168.x.x`）和跨源自定义 Header CORS 限制，因此本方案的媒体服务器直连主要面向 **iOS / Android / HarmonyOS NEXT 原生 App**；Web 端维持 `content_url` 后台中转不变。

---

## 3. 后端接口契约 (`MoviePilot`)

### 3.1 `MediaServerStreamInfo` 扩展（100% 向后兼容）
`GET /api/v1/mediaserver/stream-info` 与 `POST /api/v1/mediaserver/stream-info/music` 保持现有 `content_url`（恒为当前实例代理 URL）与 `strm_url` 不变，新增可选字段 `playback_routes`：

```json
{
  "item_id": "12345",
  "server": "客厅 Emby",
  "server_type": "emby",
  "content_url": "https://mp.example.com/api/v1/mediaserver/stream?itemid=12345&server=...",
  "strm_url": null,
  "play_session_id": "emby-psid-abc",
  "progress_sync_mode": "session",
  "playback_routes": [
    {
      "kind": "server_lan",
      "url": "http://192.168.1.10:8096/emby/Videos/12345/stream?Static=true&MediaSourceId=ms1&PlaySessionId=emby-psid-abc",
      "probe_url": "http://192.168.1.10:8096/emby/System/Ping",
      "headers": {
        "X-Emby-Token": "<user-personal-token>",
        "X-Emby-Authorization": "MediaBrowser Client=\"MoviePilot\", Device=\"iPhone\", DeviceId=\"...\", Version=\"2.0.3\""
      },
      "priority": 20,
      "requires_same_origin_auth": false
    },
    {
      "kind": "server_wan",
      "url": "https://emby.example.com/emby/Videos/12345/stream?Static=true&MediaSourceId=ms1&PlaySessionId=emby-psid-abc",
      "probe_url": "https://emby.example.com/emby/System/Ping",
      "headers": {
        "X-Emby-Token": "<user-personal-token>",
        "X-Emby-Authorization": "MediaBrowser Client=\"MoviePilot\", Device=\"iPhone\", DeviceId=\"...\", Version=\"2.0.3\""
      },
      "priority": 30,
      "requires_same_origin_auth": false
    },
    {
      "kind": "mp_proxy",
      "url": "https://mp.example.com/api/v1/mediaserver/stream?itemid=12345&server=...",
      "probe_url": null,
      "headers": {},
      "priority": 100,
      "requires_same_origin_auth": true
    }
  ]
}
```

### 3.2 容器内网与不可达地址自动过滤
后端在构建 `server_lan` / `server_wan` 候选时，自动校验并过滤以下客户端绝对不可达地址：
- `localhost`、`127.0.0.0/8`、`::1`、`0.0.0.0`
- `host.docker.internal`、`gateway.docker.internal`
- 无点号的容器服务名（如 `http://emby:8096`、`http://plex:32400`）
- Docker 默认桥接子网 `172.17.0.0/16`
- 含内嵌凭据（`user:pass@host`）或非 `http`/`https` 协议的地址

地址分类规则：
- 私网 IPv4（`192.168.0.0/16`、`10.0.0.0/8`、`172.16.0.0/12` 除 `172.17.0.0/16`、链路本地 `169.254.0.0/16`）、私网 IPv6（`fc00::/7`、`fe80::/10`）、以及 `.local` / `.lan` / `.home` / `.internal` 后缀域名归类为 `server_lan`（`priority=20`）。
- 其余公网域名或公网 IP 归类为 `server_wan`（`priority=30`）。
- 若 `host` 与 `play_host` 归一化后相同则自动去重。

### 3.3 外挂字幕与歌词
外挂字幕与 LRC 歌词体积通常小于 200 KB，继续统一走 MoviePilot 同源代理，避免跨源编码/TLS/鉴权差异影响字幕加载。

---

## 4. 跨端共享 Rust 路由规划器 (`mp-core-model`)

新增 `shared/core-rust/crates/mp-core-model/src/playback_route.rs` 并通过 UniFFI（iOS/Android）与 OHOS NAPI（鸿蒙）导出：

1. **`plan_playback_routes_json(routes_json, prefs_json, probes_json)`**：
   - 按 `prefer_strm_direct`、`prefer_server_direct` 偏好过滤候选路由；
   - 根据并发探测结果 `probes`（`url`, `reachable`, `latency_ms`）选择最优主路由：
     1. 若启用且存在 `strm_direct`：主路由为 `strm_direct`，备选队列依次包含探测可达的 `server_lan` / `server_wan` 和兜底 `mp_proxy`。
     2. 否则，若 `server_lan` 探测可达且 `latency_ms <= 350`（或仅 `server_lan` 可达）：主路由为 `server_lan`，备选为可达的 `server_wan` + `mp_proxy`。
     3. 否则，若 `server_wan` 可达：主路由为 `server_wan`，备选为 `mp_proxy`。
     4. 若全部直连探测失败或超时：主路由直接为 `mp_proxy`。
   - 返回结构化规划 `PlaybackRoutePlan`：`active`（主路由）、`fallbacks`（有序降级队列）、`route_label_zh`（`STRM 直链` / `局域网直连` / `外网直连` / `后台中转`）。
2. **`is_same_http_origin(url_a, url_b)`**：
   - 严格校验 `scheme` + `host`（大小写无关）+ 显式/默认 `port` 一致，供三端播放器在跨源 302 重定向时安全剥离直连令牌头。

---

## 5. 客户端三端实施要点 (`iOS` / `Android` / `HarmonyOS NEXT`)

1. **偏好开关**：
   - 在各端「播放偏好」页面新增 **「媒体服务器直连优先」** 开关（默认开启 `true`），并与「STRM 直链播放」独立控制。
   - 多语言文案统一录入 `shared/l10n/app.strings.json` 并通过 `tools/sync-all.py` 同步到三端。
2. **并发轻量探测与网络指纹缓存 (`PlaybackRouteResolver`)**：
   - **iOS**：使用 `NWPathMonitor` 监听网络接口变化递增 `networkEpoch`，用独立 `URLSessionConfiguration.ephemeral`（`timeoutIntervalForRequest = 0.75`）并发探测 `server_lan` / `server_wan` 的 `probe_url`。
   - **Android**：使用 `ConnectivityManager.registerDefaultNetworkCallback` 监听切网递增 `networkEpoch`，用短超时 OkHttp（`connectTimeout = 700ms`, `readTimeout = 700ms`，遵循 `allowSelfSignedTls`）并发探测。
   - **HarmonyOS NEXT**：使用 `@kit.NetworkKit` `connection.createNetConnection()` 监听 `netAvailable` / `netLost` / `netCapabilitiesChange` 递增 `networkEpoch`，用 `@kit.NetworkKit` `http`（`connectTimeout = 700`, `readTimeout = 700`）并发探测。
   - 按 `(serverName, networkEpoch)` 缓存探测结果 **5 分钟**，避免切集或连续播放重复探测；如直连起播失败则主动将对应路由写入短时负缓存（60 秒），防止反复踩坑。
3. **安全头透传与自动降级**：
   - `mp_proxy` 路由使用 MoviePilot 实例同源 `Authorization` + `Cookie`；
   - `server_lan` / `server_wan` 路由仅对与直连地址同源的请求发送 `route.headers`（`X-Emby-Token` / `X-Plex-Token` 等），跨源重定向自动剥离；
   - 播放器遇到起播错误且 `position <= 1s`（尚未成功播放）时，沿 `fallbacks` 队列自动降级重播（`strm_direct` -> `server_lan` -> `server_wan` -> `mp_proxy`），并实时刷新路由角标。
4. **可观测性提示**：
   - 在三端播放控制栏/顶部信息栏展示轻量路由角标（`局域网直连` / `外网直连` / `STRM 直链` / `后台中转`），用户可一目了然地确认流量路径。

---

## 6. 验收清单

- [x] 未绑定媒体服务器个人账号的普通用户调用 `/stream-info` 时，响应中绝不包含管理员 API Key / 全局 Token，且仅下发 `mp_proxy`（及无凭据 `strm_url`）。
- [x] 已绑定 Emby / Jellyfin / Plex 个人账号时，`/stream-info` 正确返回过滤后的 `server_lan` / `server_wan` 候选及 `probe_url`，令牌位于 `headers` 且不出现在 URL 查询串中。
- [x] 容器内网地址（`localhost`、`127.0.0.1`、`http://emby:8096`、`172.17.x.x`）自动过滤，不下发给客户端。
- [x] Rust 共享核心单元测试覆盖全部路由优先级、350ms 局域网优先、偏好开关过滤、同源比对与降级顺序。
- [x] iOS / Android / 鸿蒙三端完成并发探测、网络切换失效缓存、多级自动降级、设置开关与路由角标，且全部通过本地单测与编译。
- [x] 直连播放期间 Emby / Jellyfin / Plex 实时会话与进度同步保持 100% 正常。
