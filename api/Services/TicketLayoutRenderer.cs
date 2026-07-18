using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;

namespace RailLog.API.Services;

internal sealed class TicketLayoutRenderer : ITicketDrawingBackend, IDisposable
{
    public const int CanvasWidth = TicketLayout.CanvasWidth;
    public const int CanvasHeight = TicketLayout.CanvasHeight;
    private readonly TicketAssetStore _assets;
    private readonly Lazy<PrivateFontResource?> _trainCodeFont;
    private readonly Lazy<PrivateFontResource?> _idCodeFont;
    private Image? _background;
    private Image? _qrImage;
    private Graphics? _graphics;

    public TicketLayoutRenderer(TicketAssetStore assets)
    {
        _assets = assets;
        _trainCodeFont = new(() => LoadPrivateFont(_assets.FontPath("CODE1.OTF")));
        _idCodeFont = new(() => LoadPrivateFont(_assets.FontPath("PAPERTICKETS.OTF")));
    }

    public bool TrySetBackground(TicketStyle style, out string? error)
    {
        try
        {
            using var source = Image.FromFile(_assets.BackgroundPath(style));
            using var sourceBitmap = new Bitmap(source);
            var clone = new Bitmap(sourceBitmap.Width, sourceBitmap.Height, PixelFormat.Format32bppPArgb);
            using (var graphics = Graphics.FromImage(clone))
                graphics.DrawImage(sourceBitmap, new Rectangle(0, 0, clone.Width, clone.Height),
                    new Rectangle(0, 0, sourceBitmap.Width, sourceBitmap.Height), GraphicsUnit.Pixel);
            _background?.Dispose();
            _background = clone;
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }

    public bool TrySetQrImage(byte[] bytes, out string? error)
    {
        try
        {
            using var stream = new MemoryStream(bytes);
            using var source = Image.FromStream(stream, true, true);
            var clone = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppPArgb);
            using (var graphics = Graphics.FromImage(clone))
            {
                graphics.CompositingMode = CompositingMode.SourceCopy;
                graphics.DrawImage(source, new Rectangle(0, 0, clone.Width, clone.Height),
                    new Rectangle(0, 0, source.Width, source.Height), GraphicsUnit.Pixel);
            }
            _qrImage?.Dispose();
            _qrImage = clone;
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }

    public Bitmap Render(TicketRenderData ticket)
    {
        var bitmap = new Bitmap(CanvasWidth, CanvasHeight, PixelFormat.Format32bppPArgb);
        bitmap.SetResolution(144, 144);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        graphics.Clear(Color.Transparent);
        if (_background is not null)
            graphics.DrawImage(_background, new Rectangle(0, 0, CanvasWidth, CanvasHeight),
                new Rectangle(0, 0, _background.Width, _background.Height), GraphicsUnit.Pixel);
        _graphics = graphics;
        try { TicketLayout.Draw(this, ticket, "png"); }
        finally { _graphics = null; }
        return bitmap;
    }

    public TicketTextMetrics Measure(string text, TicketFont spec)
    {
        using var font = CreateFont(spec);
        using var format = new StringFormat(StringFormat.GenericTypographic);
        var size = Graphics.MeasureString(text, font, int.MaxValue, format);
        return new(size.Width, size.Height, size.Height);
    }

    public void DrawText(string text, float x, float y, TicketFont spec, TicketColor color,
        float scaleX = 1, float scaleY = 1)
    {
        using var font = CreateFont(spec);
        using var brush = new SolidBrush(ToColor(color));
        using var format = new StringFormat(StringFormat.GenericTypographic);
        var state = Graphics.Save();
        Graphics.TranslateTransform(x, y);
        Graphics.ScaleTransform(scaleX, scaleY);
        DrawWeightedString(text, font, brush, 0, 0, format, spec.Bold);
        Graphics.Restore(state);
    }

    public void DrawLine(float x1, float y1, float x2, float y2, TicketColor color, float width)
    {
        using var pen = new Pen(ToColor(color), width)
            { StartCap = LineCap.Flat, EndCap = LineCap.Flat, LineJoin = LineJoin.Miter };
        Graphics.DrawLine(pen, x1, y1, x2, y2);
    }

    public void DrawDashedRectangle(TicketRect bounds, TicketColor color, float width, float dash, float gap)
    {
        using var pen = new Pen(ToColor(color), width) { DashPattern = [dash, gap] };
        Graphics.DrawRectangle(pen, bounds.Left, bounds.Top, bounds.Width, bounds.Height);
    }

    public void DrawQr(TicketRect bounds, TicketColor color)
    {
        if (_qrImage is null) return;
        Graphics.DrawImage(_qrImage, new RectangleF(bounds.Left, bounds.Top, bounds.Width, bounds.Height),
            new RectangleF(0, 0, _qrImage.Width, _qrImage.Height), GraphicsUnit.Pixel);
    }

    public void DrawWatermark(string text, float centerX, float centerY, float angle, TicketFont spec,
        TicketColor color)
    {
        using var font = CreateFont(spec);
        using var brush = new SolidBrush(ToColor(color));
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        var state = Graphics.Save();
        Graphics.TranslateTransform(centerX, centerY);
        Graphics.RotateTransform(angle);
        Graphics.DrawString(text, font, brush, 0, 0, format);
        Graphics.Restore(state);
    }

    private Graphics Graphics => _graphics ?? throw new InvalidOperationException("渲染上下文尚未初始化");
    private static Color ToColor(TicketColor color) => Color.FromArgb(color.A, color.R, color.G, color.B);

    private void DrawWeightedString(string text, Font font, Brush brush, float x, float y,
        StringFormat format, bool bold)
    {
        Graphics.DrawString(text, font, brush, x, y, format);
        if (bold) Graphics.DrawString(text, font, brush, x + 1.1f, y, format);
    }

    private Font CreateFont(TicketFont spec)
    {
        var style = spec.Bold ? FontStyle.Bold : FontStyle.Regular;
        var family = spec.Family switch
        {
            TicketFontFamily.TrainCode => _trainCodeFont.Value?.Family,
            TicketFontFamily.IdCode => _idCodeFont.Value?.Family,
            _ => null
        };
        var name = spec.Family switch
        {
            TicketFontFamily.Hei => "SimHei",
            TicketFontFamily.Arial => "Arial",
            _ => "SimSun"
        };
        try
        {
            if (family is not null)
            {
                var available = family.IsStyleAvailable(style) ? style : FontStyle.Regular;
                return new Font(family, spec.Size * TicketLayout.TextScale, available, GraphicsUnit.Pixel);
            }
            return new Font(name, spec.Size * TicketLayout.TextScale, style, GraphicsUnit.Pixel);
        }
        catch
        {
            return new Font(FontFamily.GenericSansSerif, spec.Size * TicketLayout.TextScale, style,
                GraphicsUnit.Pixel);
        }
    }

    private static PrivateFontResource? LoadPrivateFont(string path)
    {
        try
        {
            var collection = new PrivateFontCollection();
            collection.AddFontFile(path);
            return collection.Families.Length == 0 ? null : new(collection, collection.Families[0]);
        }
        catch { return null; }
    }

    private sealed record PrivateFontResource(PrivateFontCollection Collection, FontFamily Family);

    public void Dispose()
    {
        _background?.Dispose();
        _qrImage?.Dispose();
        if (_trainCodeFont.IsValueCreated) _trainCodeFont.Value?.Collection.Dispose();
        if (_idCodeFont.IsValueCreated) _idCodeFont.Value?.Collection.Dispose();
    }
}
