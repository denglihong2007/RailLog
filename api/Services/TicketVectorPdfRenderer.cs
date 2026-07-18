using SkiaSharp;

namespace RailLog.API.Services;

internal sealed class TicketVectorPdfRenderer : ITicketDrawingBackend, IDisposable
{
    private readonly TicketAssetStore _assets;
    private readonly SKTypeface _train;
    private readonly SKTypeface _id;
    private readonly SKTypeface _song;
    private readonly SKTypeface _hei;
    private readonly SKTypeface _arial;
    private SKCanvas? _canvas;
    private SKBitmap? _qr;

    public TicketVectorPdfRenderer(TicketAssetStore assets)
    {
        _assets = assets;
        _train = SKTypeface.FromFile(assets.FontPath("CODE1.OTF"))
            ?? throw new TicketAssetException("无法读取车次字体");
        _id = SKTypeface.FromFile(assets.FontPath("PAPERTICKETS.OTF"))
            ?? throw new TicketAssetException("无法读取票纸字体");
        _song = SystemTypeface("SimSun", '中', SKFontStyle.Normal);
        _hei = SystemTypeface("SimHei", '中', SKFontStyle.Bold);
        _arial = SystemTypeface("Arial", 'A', SKFontStyle.Normal);
    }

    public byte[] Render(TicketRenderData ticket, byte[] qrBytes)
    {
        using var qr = SKBitmap.Decode(qrBytes)
            ?? throw new TicketAssetException("二维码图片格式无效");
        using var stream = new MemoryStream();
        using (var document = SKDocument.CreatePdf(stream))
        {
            _canvas = document.BeginPage(TicketLayout.CanvasWidth, TicketLayout.CanvasHeight);
            _qr = qr;
            try
            {
                if (ticket.Style == TicketStyle.Blue)
                {
                    using var background = SKBitmap.Decode(_assets.BackgroundPath(TicketStyle.Blue))
                        ?? throw new TicketAssetException("无法读取蓝票底纹");
                    Canvas.DrawBitmap(background, new SKRect(
                        0, 0, TicketLayout.CanvasWidth, TicketLayout.CanvasHeight));
                }
                TicketLayout.Draw(this, ticket, "pdf");
            }
            finally
            {
                _canvas = null;
                _qr = null;
            }
            document.EndPage();
            document.Close();
        }
        return stream.ToArray();
    }

    public TicketTextMetrics Measure(string text, TicketFont spec)
    {
        using var font = CreateFont(spec, text);
        var width = font.MeasureText(text);
        var height = Scaled(spec.Size);
        return new(width, height, height + font.Metrics.Descent);
    }

    public void DrawText(string text, float x, float y, TicketFont spec, TicketColor color,
        float scaleX = 1, float scaleY = 1)
    {
        using var font = CreateFont(spec, text);
        using var paint = Fill(color);
        Canvas.Save();
        Canvas.Translate(x, y);
        Canvas.Scale(scaleX, scaleY);
        Canvas.DrawText(text, 0, Scaled(spec.Size), font, paint);
        Canvas.Restore();
    }

    public void DrawLine(float x1, float y1, float x2, float y2, TicketColor color, float width)
    {
        using var paint = Stroke(color, width);
        Canvas.DrawLine(x1, y1, x2, y2, paint);
    }

    public void DrawDashedRectangle(TicketRect bounds, TicketColor color, float width, float dash, float gap)
    {
        using var paint = Stroke(color, width);
        paint.PathEffect = SKPathEffect.CreateDash([dash, gap], 0);
        Canvas.DrawRect(new SKRect(bounds.Left, bounds.Top, bounds.Right, bounds.Bottom), paint);
    }

    public void DrawQr(TicketRect bounds, TicketColor color)
    {
        if (_qr is null) return;
        using var paint = Fill(color);
        var sx = bounds.Width / _qr.Width;
        var sy = bounds.Height / _qr.Height;
        for (var y = 0; y < _qr.Height; y++)
        {
            var start = -1;
            for (var x = 0; x <= _qr.Width; x++)
            {
                var dark = x < _qr.Width && IsDark(_qr.GetPixel(x, y));
                if (dark && start < 0) start = x;
                if (!dark && start >= 0)
                {
                    Canvas.DrawRect(new SKRect(bounds.Left + start * sx, bounds.Top + y * sy,
                        bounds.Left + x * sx, bounds.Top + (y + 1) * sy), paint);
                    start = -1;
                }
            }
        }
    }

    public void DrawWatermark(string text, float centerX, float centerY, float angle, TicketFont spec,
        TicketColor color)
    {
        var metrics = Measure(text, spec);
        Canvas.Save();
        Canvas.Translate(centerX, centerY);
        Canvas.RotateDegrees(angle);
        DrawText(text, -metrics.Width / 2, -metrics.Height / 2, spec, color);
        Canvas.Restore();
    }

    private SKCanvas Canvas => _canvas ?? throw new InvalidOperationException("渲染上下文尚未初始化");

    private SKFont CreateFont(TicketFont spec, string text)
    {
        var typeface = Typeface(spec.Family, text);
        var embolden = spec.Bold && spec.Family != TicketFontFamily.Hei;
        return new(typeface, Scaled(spec.Size)) { Embolden = embolden };
    }

    private SKTypeface Typeface(TicketFontFamily family, string text)
    {
        var selected = family switch
        {
            TicketFontFamily.TrainCode => _train,
            TicketFontFamily.IdCode => _id,
            TicketFontFamily.Hei => _hei,
            TicketFontFamily.Arial => _arial,
            _ => _song
        };
        return selected.ContainsGlyphs(text) ? selected : _song;
    }

    private static bool IsDark(SKColor pixel) =>
        pixel.Alpha > 64 && pixel.Red + pixel.Green + pixel.Blue < 384;
    private static float Scaled(float size) => size * TicketLayout.TextScale;
    private static SKColor ToColor(TicketColor color) => new(color.R, color.G, color.B, color.A);
    private static SKPaint Fill(TicketColor color) =>
        new() { Color = ToColor(color), IsAntialias = true, Style = SKPaintStyle.Fill };
    private static SKPaint Stroke(TicketColor color, float width) =>
        new() { Color = ToColor(color), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = width };

    private static SKTypeface SystemTypeface(string family, char sample, SKFontStyle style)
    {
        var preferred = SKFontManager.Default.MatchFamily(family, style);
        if (preferred is not null && preferred.ContainsGlyph(sample)) return preferred;
        preferred?.Dispose();
        return SKFontManager.Default.MatchCharacter(family, style, ["zh-CN", "zh-Hans"], sample)
            ?? throw new TicketAssetException($"服务器缺少字体 {family}");
    }

    public void Dispose()
    {
        _train.Dispose();
        _id.Dispose();
        _song.Dispose();
        _hei.Dispose();
        _arial.Dispose();
    }
}
