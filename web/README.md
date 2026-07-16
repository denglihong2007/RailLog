# RailLog 官网

RailLog 的官方网站与下载页面，生产域名为 `https://www.raillog.top`。

## 开发

```sh
npm install
npm run dev
```

开发服务器会将 `/api` 代理到 `http://localhost:5149`。

## 生产构建

```sh
npm run build
```

生产构建通过 `.env.production` 请求 `https://api.raillog.top`。构建结果位于 `dist`，部署时应确保 `/download` 能访问 `dist/download/index.html`。

国内网盘链接由 API 服务端配置维护：

- `Updates__WindowsDomesticDownloadUrl`
- `Updates__AndroidDomesticDownloadUrl`
- `Updates__DomesticDownloadName`
