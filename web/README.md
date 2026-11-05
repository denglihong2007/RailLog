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

## 管理后台

管理后台与官网在同一个 Vite 工程内，页面入口是 `admin/index.html`，源码位于 `src/admin`。开发时访问 `http://localhost:55634/admin`；生产构建会生成 `dist/admin/index.html`，静态部署时需让 `/admin` 指向它。它和管理 API 共用 `VITE_API_URL`，生产构建会直接请求 `https://api.raillog.top`，因此该来源必须出现在 API 的 `Cors:AllowedOrigins` 中（默认已包含 `https://www.raillog.top`）。

登录使用拥有管理员权限的 RailLog 账户（邮箱 + 密码）。服务端在 `appsettings.json` 的 `Admin:UserIds` 中维护白名单（GUID 有无连字符均可），令牌沿用账户的普通登录令牌并保存在浏览器 localStorage 中，默认有效期 30 天。后台目前支持：

- 公告管理（写入数据库，并同步到 App 的公告接口）
- 用户搜索、查看用户全部行程（含已删除）；修改用户资料与删除用户
- 新增、编辑、软删除、恢复用户行程
- 全站排行榜与站点统计；点选用户、行程或要素可直接进入对应行程或评价，便于纠正影响排名的数据
- 评价管理：按内容、用户、实体或车次检索评价，查看详情并删除（删除会清除回应并触发作者成就重算）
- 疑似重复行程：按「同一用户 + 同一车次 + 同一乘车日期 + 相同始发终到站、票价、里程」分组，逐条删除或保留最早录入的一条
- 等级与成就（同一个页面）：按用户已解锁成就的经验总和统计各等级人数，并调整 LV1–LV6 的经验门槛；点选等级会跳到按该等级过滤的用户列表，用户也可按等级筛选或按邮箱、昵称、ID 搜索。保存后服务端单飞地在后台重算全站成就（重算期间的重复保存会合并成一次），页面展示进度并在完成后自动刷新人数；App 与官网会从 `/api/user-levels` 拉取新配置。成就列表只读，可查看达成人数与具体达成记录
- PDF 下载管理：设置下载密码，并查看网页端生成的 24 小时下载请求 Key（可按乘车人或脱敏证件号搜索，含关联行程、撤销与清理过期）
- 数据备份：立即生成快照下载，下载已保留的历史备份文件，或输入文件名后删除某个备份
- 审计日志：追加记录删除、资料修改、等级门槛、下载密码与请求 Key、备份下载/删除、手动时刻表同步等操作，并保存操作时的管理员名称
- 历史时刻表同步：查看本地版本、上次/下次同步时间，手动触发同步并检查 GitHub Release 上缺失的版本

国内网盘链接由 API 服务端配置维护：

- `Updates__AndroidDomesticDownloadUrl`
- `Updates__DomesticDownloadName`
