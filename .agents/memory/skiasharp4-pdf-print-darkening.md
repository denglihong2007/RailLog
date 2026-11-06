# SkiaSharp 4 打印更浓

*迁移自 Claude Code 项目记忆 · 更新于 2026-10-21*

2.6.0 升级 SkiaSharp 3.119.1 → 4.153.1（Skia m119→m153）后，票面 PDF 的可见内容没变（MuPDF/PDFium 在 150–1200 dpi 下墨量比 0.999–1.0001），但结构变了：

- **红票**（无底纹图）：旧版把可见文字画进页面内容流的内联矢量路径，另有一层 `/ca 0` 的隐形文字；新版改成 Type3 字体（字体对象 12→39，内容流 824 KB→31 KB），隐形层消失。打印变浓的反馈都来自红票，所以问题在这里，不是底纹色彩空间。
- **蓝票**：另有一处变化，底纹图从 `/DeviceRGB` 变成 `ICCBased`（嵌入 Skia sRGB profile），图像字节不变。

Type3 字形无 hinting，由打印驱动/RIP 自己光栅化，Adobe 文档承认 Type3 会显得更粗；旧版是普通页面路径，走驱动正常的矢量路径管线。

验证办法：看二维码/线条是否也变浓（它们两版完全一样）——只有文字变粗就基本锁定 Type3；或让打印店用「作为图像打印 600 dpi」对比。

修复选项：回退 SkiaSharp 到 3.119.1；或在 `TicketVectorPdfRenderer.DrawText` 里用 `SKFont.GetGlyphPath` 自己画路径（已实测：PDF 里不再有字体，像素差约 0.7% 仅来自抗锯齿）。对比 harness 在 `api/.tmp/skia-cmp`。
