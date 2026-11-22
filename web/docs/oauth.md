# 账户授权（OAuth 2.0）

第三方应用需要确认「当前用户就是某个 RailLog 账户」时，使用 RailLog 提供的 OAuth 2.0 授权码流程。RailLog 只承担身份确认，不向第三方下发行程数据；行程仍通过[公开接口](./users.md)读取。

## 接入前提

客户端需要在 RailLog 登记后才能使用，登记时确定：

| 项目 | 说明 |
| --- | --- |
| `client_id` | 应用标识，例如 `rk_1a2b3c4d5e6f7a8b`。 |
| `client_secret` | 机密客户端凭据，只下发一次，服务端保存哈希。 |
| 回调地址 | 精确匹配，不做前缀或通配匹配。移动端可以是私有 scheme，例如 `railkale://oauth/callback`。 |
| 权限范围 | 目前只有 `profile`。 |

请通过仓库 issue 或邮件联系维护者登记，不支持自助注册。

## 流程

1. 客户端生成 PKCE 参数：`code_verifier` 为 43 至 128 位无保留字符，`code_challenge = BASE64URL(SHA256(code_verifier))`。
2. 在系统浏览器中打开授权页：
   ```text
   https://www.raillog.top/oauth/?client_id=...&redirect_uri=...&response_type=code&scope=profile&state=...&code_challenge=...&code_challenge_method=S256
   ```
3. 用户登录 RailLog 并确认授权后，浏览器跳回回调地址，携带 `code` 与 `state`。
4. 客户端**服务端**用 `client_secret` 换取令牌：
   ```bash
   curl -X POST "https://api.raillog.top/api/oauth/token" \
     -u "CLIENT_ID:CLIENT_SECRET" \
     -d "grant_type=authorization_code" \
     -d "code=CODE" \
     -d "redirect_uri=railkale://oauth/callback" \
     -d "code_verifier=VERIFIER"
   ```
5. 使用访问令牌查询账户 ID：
   ```bash
   curl "https://api.raillog.top/api/oauth/userinfo" \
     -H "Authorization: Bearer ACCESS_TOKEN"
   ```
   响应中的 `sub` 就是 RailLog 用户 ID，可以安全地作为绑定结果保存。

## 授权页参数

`https://www.raillog.top/oauth/` 接受以下查询参数：

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `client_id` | 是 | 登记的应用标识。 |
| `redirect_uri` | 是 | 必须与登记值完全一致。 |
| `response_type` | 是 | 固定为 `code`。 |
| `scope` | 否 | 默认 `profile`。 |
| `state` | 是 | 客户端生成，回调时原样返回。 |
| `code_challenge` | 是 | PKCE 挑战值，仅支持 `S256`。 |
| `code_challenge_method` | 是 | 固定为 `S256`。 |

参数不完整、应用停用或回调地址不匹配时，授权页会显示错误，不会跳转。

## 令牌端点

<Badge type="tip" text="POST" /> `/api/oauth/token`

请求体为 `application/x-www-form-urlencoded`，客户端凭据使用 HTTP Basic。

| `grant_type` | 必填参数 | 说明 |
| --- | --- | --- |
| `authorization_code` | `code`、`redirect_uri`、`code_verifier` | 授权码一次性使用，有效期 5 分钟。 |
| `refresh_token` | `refresh_token` | 刷新令牌轮换，旧令牌立即失效。 |

响应字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `accessToken` | string | 访问令牌，有效期 1 小时。 |
| `tokenType` | string | 固定为 `Bearer`。 |
| `expiresIn` | integer | 访问令牌剩余有效秒数。 |
| `refreshToken` | string | 刷新令牌，有效期 90 天；每次刷新都会换新的。 |
| `scope` | string | 本次授权的权限范围。 |

## 用户信息

<Badge type="tip" text="GET" /> `/api/oauth/userinfo`

请求头携带 `Authorization: Bearer ACCESS_TOKEN`，返回：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `sub` | string | RailLog 用户 ID，等同于公开接口里的 `userId`。 |
| `name` | string | 用户昵称。 |
| `picture` | `string \| null` | 头像 URL；未设置时为 `null`。 |

## 撤销

<Badge type="tip" text="POST" /> `/api/oauth/revoke`

请求体为 `application/x-www-form-urlencoded`，携带 `token`，客户端凭据使用 HTTP Basic。`token_type_hint` 可选，服务端会自动判断令牌类型。

撤销 `refresh_token` 时，同一应用下该用户的访问令牌会一并失效，**解绑请撤销刷新令牌**；只撤销访问令牌时不影响刷新令牌。无论令牌是否存在都返回 `200`，避免泄露令牌状态。

用户解除授权使用 `DELETE /api/oauth/consents/{clientId}`（需要用户的 RailLog 登录令牌）；解除后该应用名下这个用户的访问令牌和刷新令牌会全部失效。

## 错误响应

令牌端点失败时返回 JSON：

```json
{ "error": "invalid_grant", "errorDescription": "授权码无效、已过期或参数不匹配" }
```

| `error` | HTTP 状态 | 含义 |
| --- | --- | --- |
| `invalid_request` | 400 | 缺少参数或参数格式错误。 |
| `invalid_client` | 401 | `client_id` 或 `client_secret` 错误，或应用已停用。 |
| `invalid_grant` | 400 | 授权码或刷新令牌无效、过期、已使用。 |
| `unsupported_grant_type` | 400 | 不支持的 `grant_type`。 |
| `insufficient_scope` | 403 | 令牌缺少访问该资源所需的权限。 |

## 安全要求

- `code_verifier` 必须由客户端生成并只在本地保存，不要出现在回调 URL 中。
- `client_secret` 只能保存在服务端，不要打进移动端安装包。
- 回调时必须校验 `state` 与发起时一致。
- 授权码、访问令牌、刷新令牌都只保存哈希；丢失后只能重新授权。
