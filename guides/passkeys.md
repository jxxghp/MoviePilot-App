# 通行密钥登录

[返回连接说明](connection.md)

先更新 App 和实例的 [3.2.0 前端资源](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.0)。服务器开启通行密钥登录后，原生登录页会显示“使用通行密钥登录”。首次绑定请在浏览器的用户认证设置中完成。

使用证书有效的 HTTPS 地址，并确保服务器的 `APP_DOMAIN` 与实际访问入口一致。局域网 HTTP 地址可以使用密码登录，通行密钥需要安全连接。

点一次登录按钮后，App 请求当前实例的挑战并打开 iOS 系统认证会话。验证页自动唤起系统通行密钥请求，无需再点“继续”；完成后由 App 换取原有登录会话并进入首页。取消会回到原生登录表单，保持登录开关与密码登录共用。

为支持任意自部署域名和个人重签，认证使用临时的系统网页会话，系统可能显示认证窗口。直接使用 App 的原生凭证 API 需要域名与签名的 Associated Domains 关联，不能假定所有自部署实例都具备该条件。详见 [Apple 通行密钥说明](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)。

事务令牌只在 App 的当前请求内存中保留。系统验证页只处理公开挑战与签名断言，不加载完整网页登录、读取业务账户或保存会话。结果绑定当前实例、随机状态、挑战和有效期，由既有 MoviePilot 后端完成最终验证。切换实例、取消或过期后，旧结果不能继续登录。
