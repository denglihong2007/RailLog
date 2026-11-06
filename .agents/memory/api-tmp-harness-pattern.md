# 后端验证靠 api/.tmp harness

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-10*

`api/` 下**没有测试工程**（只有 `RailLog.API.csproj`），`app/test/` 那套纯 Dart 测试覆盖不到后端。验证后端改动的方式是在 `api/.tmp/<名字>/` 建一个一次性控制台 harness：

- `.csproj`：`net10.0` + `<FrameworkReference Include="Microsoft.AspNetCore.App" />` + `ProjectReference` 指回 `..\..\RailLog.API.csproj`。
- 要看私有静态方法（如 `TicketGeneratorService.FormatCarriageSeat` / `FormatSeatClass`）直接反射取，别为了测试改生产代码可见性。
- 需要数据库时用临时 SQLite：`ConfigurationBuilder().AddInMemoryCollection(["ConnectionStrings:RailLog" = $"Data Source={临时路径}"])`，`new RailLogDatabase(config, new FakeEnvironment(), new MemoryCache(...))` + `InitializeAsync()`，最后 `SqliteConnection.ClearAllPools()` 才能删掉文件。`IWebHostEnvironment` 可以自己写个假实现。
- 断成就时注意 `AchievementEngine.Evaluate` 返回的是**全部定义**，未解锁的 `TriggerTripId` 为 null —— 要判 `TriggerTripId is not null`，不能只判条目存在，否则每条都 PASS。（`RailLogDatabase.RecalculateAchievementsAsync` 也是这么筛的。）

`api/.tmp/` 被 git 忽略，所以这些 harness 只存在于本地工作区，新克隆或换机器就没有了；现成的例子：`achcheck`（成就）、`hgcheck`（首页热门排序）、`seatcheck`（加车/席别代用）。

**本地 dev server 在跑时 `api/bin` 被锁**（`RailLog.API.exe`/`.dll` 被占用，MSB3021/MSB3027 复制失败，但编译本身是过的）。别去杀用户的进程，改用重定向输出验证：

```bash
dotnet build api/RailLog.API.csproj -p:UseAppHost=false -p:OutputPath=<临时目录>   # 只验编译
cd api/.tmp/<harness> && dotnet build -p:BuildProjectReferences=false              # 不重建 API
cp <临时目录>/RailLog.API.dll bin/Debug/net10.0/ && dotnet run --no-build         # 用新引擎跑 harness
```

注意 PowerShell/bash 里给 `-p:OutputPath=` 传路径**不要带结尾反斜杠**（会把 `--nologo` 之类吞进路径，在 `api/` 下生成一个垃圾目录）。

**Why:** 后端改动的验证方式不写在仓库里，每次都要重新想一遍，还容易踩上面那个 `Evaluate` 假 PASS。
**How to apply:** 改后端逻辑时直接照 `api/.tmp/hgcheck` 的结构抄一份，别去找不存在的测试工程。相关：[achievement-icon-contract](./achievement-icon-contract.md)
