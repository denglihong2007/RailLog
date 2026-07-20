using System.Drawing;
using System.Drawing.Imaging;

namespace RailLog.API.Services;

public sealed class TicketRenderer(TicketAssetStore assets)
{
    public const int CanvasWidth = TicketLayoutRenderer.CanvasWidth;
    public const int CanvasHeight = TicketLayoutRenderer.CanvasHeight;
    private const int RedPngPadding = 64;

    public byte[] RenderPng(TicketRenderData ticket, byte[] qrBytes, bool includeBackground)
    {
        using var bitmap = RenderBitmap(ticket, qrBytes, includeBackground);
        using var stream = new MemoryStream();
        if (ticket.Style == TicketStyle.Red && includeBackground)
        {
            using var expanded = AddRedPngBackground(bitmap);
            expanded.Save(stream, ImageFormat.Png);
        }
        else
        {
            bitmap.Save(stream, ImageFormat.Png);
        }
        return stream.ToArray();
    }

    public byte[] RenderPdf(TicketRenderData ticket, byte[] qrBytes)
    {
        using var renderer = new TicketVectorPdfRenderer(assets);
        return renderer.Render(ticket, qrBytes);
    }

    private Bitmap RenderBitmap(TicketRenderData ticket, byte[] qrBytes, bool includeBackground)
    {
        using var renderer = new TicketLayoutRenderer(assets);
        if (includeBackground && !renderer.TrySetBackground(ticket.Style, out var backgroundError))
            throw new TicketAssetException($"无法读取车票底纹：{backgroundError}");
        if (!renderer.TrySetQrImage(qrBytes, out var qrError))
            throw new TicketAssetException($"二维码图片格式无效：{qrError}");
        return renderer.Render(ticket);
    }

    private static Bitmap AddRedPngBackground(Bitmap ticket)
    {
        var expanded = new Bitmap(ticket.Width + RedPngPadding * 2,
            ticket.Height + RedPngPadding * 2, PixelFormat.Format32bppPArgb);
        expanded.SetResolution(ticket.HorizontalResolution, ticket.VerticalResolution);
        using var graphics = Graphics.FromImage(expanded);
        graphics.Clear(Color.White);
        graphics.DrawImageUnscaled(ticket, RedPngPadding, RedPngPadding);
        return expanded;
    }
}

public sealed record TicketRenderData(
    TicketStyle Style,
    string TicketNumber,
    string FromStation,
    string FromPinyin,
    string ToStation,
    string ToPinyin,
    string TrainNumber,
    DateTime Departure,
    string CarriageSeat,
    double Price,
    string SeatClass,
    string Passenger,
    string MaskedId,
    string RestrictionText,
    string MemorialText,
    string NoticeLine1,
    string NoticeLine2,
    string SerialNumber);
