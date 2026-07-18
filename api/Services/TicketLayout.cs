using System.Text.RegularExpressions;

namespace RailLog.API.Services;

internal enum TicketFontFamily { Song, Hei, Arial, TrainCode, IdCode }

internal readonly record struct TicketFont(float Size, TicketFontFamily Family = TicketFontFamily.Song,
    bool Bold = false);
internal readonly record struct TicketTextMetrics(float Width, float Height, float InkBottom);
internal readonly record struct TicketColor(byte A, byte R, byte G, byte B)
{
    public static TicketColor Rgb(byte r, byte g, byte b) => new(255, r, g, b);
}
internal readonly record struct TicketRect(float Left, float Top, float Width, float Height)
{
    public float Right => Left + Width;
    public float Bottom => Top + Height;
}
internal readonly record struct TicketTextRun(string Text, TicketFont Font, float Padding = 0,
    float ScaleX = 1, float OffsetY = 0);

internal interface ITicketDrawingBackend
{
    TicketTextMetrics Measure(string text, TicketFont font);
    void DrawText(string text, float x, float y, TicketFont font, TicketColor color,
        float scaleX = 1, float scaleY = 1);
    void DrawLine(float x1, float y1, float x2, float y2, TicketColor color, float width);
    void DrawDashedRectangle(TicketRect bounds, TicketColor color, float width, float dash, float gap);
    void DrawQr(TicketRect bounds, TicketColor color);
    void DrawWatermark(string text, float centerX, float centerY, float angle, TicketFont font,
        TicketColor color);
}

internal static class TicketLayout
{
    public const int CanvasWidth = 1800;
    public const int CanvasHeight = 1120;
    public const float TextScale = 1.15f;
    private static readonly TicketColor Black = TicketColor.Rgb(25, 25, 25);
    private static readonly TicketColor Red = TicketColor.Rgb(219, 49, 70);

    public static void Draw(ITicketDrawingBackend canvas, TicketRenderData ticket, string ticketType)
    {
        var blue = ticket.Style == TicketStyle.Blue;
        var stationY = blue ? 154f : 202f;
        var pinyinY = blue ? 260f : 302f;
        var trainY = blue ? 167f : 215f;
        var arrowY = blue ? 264f : 312f;
        var dateY = blue ? 322f : 370f;
        var priceY = blue ? 420f : 468f;
        var memorialY = blue ? 633f : 642f;
        var identityY = blue ? 737f : 740f;

        canvas.DrawText(ticket.TicketNumber, 112, blue ? 44 : 100,
            new TicketFont(76, TicketFontFamily.Arial), Red);
        var expand = Station(ticket.FromStation).Length >= 5 && Station(ticket.ToStation).Length >= 5;
        DrawStation(canvas, ticket.FromStation, 360, stationY, expand);
        DrawTracked(canvas, ticket.FromPinyin, 80, pinyinY, 560,
            new TicketFont(46, TicketFontFamily.Song, true), 3, scaleY: 1.2f);

        var trainFont = new TicketFont(84, TicketFontFamily.TrainCode);
        var trainMetrics = canvas.Measure(ticket.TrainNumber, trainFont);
        var trainBottom = trainY + trainMetrics.InkBottom;
        if (trainBottom > arrowY - 12) trainY -= trainBottom - (arrowY - 12);
        DrawTracked(canvas, ticket.TrainNumber, 650, trainY, 500, trainFont, 7);
        canvas.DrawLine(900 - 300 / 2, arrowY, 900 + 300 / 2, arrowY, Black, 3.5f);
        canvas.DrawLine(868 + 300 / 2, arrowY - 8, 900 + 300 / 2, arrowY, Black, 3.5f);

        var toLeft = DrawStation(canvas, ticket.ToStation, 1400, stationY, expand);
        DrawTracked(canvas, ticket.ToPinyin, 1120, pinyinY, 560,
            new TicketFont(43, TicketFontFamily.Song, true), 6, scaleY: 1.2f);
        DrawInline(canvas, 112, dateY,
            new(ticket.Departure.ToString("yyyy"), new(73, TicketFontFamily.IdCode)),
            SmallLabel("年", 5),
            new(ticket.Departure.ToString("MM"), new(73, TicketFontFamily.IdCode), 6),
            SmallLabel("月", 5),
            new(ticket.Departure.ToString("dd"), new(73, TicketFontFamily.IdCode), 6),
            SmallLabel("日", 5),
            new(ticket.Departure.ToString("HH:mm"), new(73, TicketFontFamily.IdCode), 22),
            SmallLabel("开", 5));
        DrawInline(canvas, toLeft, dateY, SeatRuns(ticket.CarriageSeat).ToArray());
        DrawInline(canvas, 112, priceY,
            new("￥", new(75)),
            new(ticket.Price.ToString("F1"), new(75, TicketFontFamily.IdCode)),
            SmallLabel("元", 9));
        canvas.DrawText(ticket.SeatClass, 1230, priceY, new TicketFont(63, Bold: true), Black);
        canvas.DrawText("仅供收藏纪念使用", 112, memorialY,
            new TicketFont(63, Bold: true), Black);
        DrawIdAndName(canvas, ticket.MaskedId, ticket.Passenger, 112, identityY - 8);

        var notice = new TicketRect(200, 819, 1010, 146);
        canvas.DrawDashedRectangle(notice, Black, 3, 12, 5);
        DrawCenteredLines(canvas, [ticket.NoticeLine1, ticket.NoticeLine2], notice,
            new TicketFont(50, Bold: true), 2);
        canvas.DrawText(ticket.SerialNumber, 160, blue ? 1023 : 987,
            new TicketFont(56, Bold: true), Black, scaleX: .9f);
        var qrBounds = blue
            ? new TicketRect(1443, identityY, 217, 217)
            : new TicketRect(1352, 745, 300, 300);
        canvas.DrawQr(qrBounds, Black);
        if (ticketType != "pdf")
        {
            canvas.DrawWatermark("纪念票 · 非乘车凭证", 900, blue ? 535 : 560, -19,
                new TicketFont(118, Bold: true), blue
                    ? new TicketColor(34, 45, 100, 120)
                    : new TicketColor(54, 180, 20, 35));
        }
    }

    private static float DrawStation(ITicketDrawingBackend canvas, string value, float center,
        float y, bool expand)
    {
        var station = Station(value);
        if (station.Length == 2) station = $"{station[0]}　{station[1]}";
        var font = new TicketFont(expand ? 92 : 82, TicketFontFamily.Hei, true);
        var suffixFont = new TicketFont(48, Bold: true);
        var hanWidth = canvas.Measure("中", font).Width;
        var widths = station.Select(c => c == '　' ? hanWidth : canvas.Measure(c.ToString(), font).Width).ToArray();
        var nameWidth = widths.Sum() + Math.Max(0, station.Length - 1) * 12;
        var suffix = canvas.Measure("站", suffixFont);
        var nameHeight = canvas.Measure(station, font).Height;
        var left = center - (nameWidth + 15 + suffix.Width) / 2;
        var x = left;
        for (var i = 0; i < station.Length; i++)
        {
            if (station[i] != '　') canvas.DrawText(station[i].ToString(), x, y, font, Black);
            x += widths[i] + 12;
        }
        canvas.DrawText("站", left + nameWidth + 15, y + (nameHeight - suffix.Height) / 2,
            suffixFont, Black);
        return left;
    }

    private static void DrawTracked(ITicketDrawingBackend canvas, string text, float x, float y,
        float width, TicketFont font, float tracking, float scaleY = 1)
    {
        var measured = MeasureTracked(canvas, text, font, tracking);
        x += (width - measured) / 2;
        foreach (var character in text)
        {
            var value = character.ToString();
            canvas.DrawText(value, x, y, font, Black, scaleY: scaleY);
            x += canvas.Measure(value, font).Width + tracking;
        }
    }

    private static float MeasureTracked(ITicketDrawingBackend canvas, string text, TicketFont font,
        float tracking) => text.Sum(c => canvas.Measure(c.ToString(), font).Width) +
                           Math.Max(0, text.Length - 1) * tracking;

    private static void DrawInline(ITicketDrawingBackend canvas, float x, float y,
        params TicketTextRun[] runs)
    {
        var heights = runs.Select(run => canvas.Measure(run.Text, run.Font).Height).ToArray();
        var max = heights.DefaultIfEmpty().Max();
        for (var i = 0; i < runs.Length; i++)
        {
            var run = runs[i];
            x += run.Padding;
            canvas.DrawText(run.Text, x, y + (max - heights[i]) / 2 + run.OffsetY,
                run.Font, Black, run.ScaleX);
            x += canvas.Measure(run.Text, run.Font).Width * run.ScaleX;
        }
    }

    private static void DrawIdAndName(ITicketDrawingBackend canvas, string id, string name,
        float x, float y)
    {
        var idFont = new TicketFont(64, TicketFontFamily.IdCode);
        foreach (var character in id)
        {
            var value = character.ToString();
            canvas.DrawText(value, x, y, idFont, Black);
            x += canvas.Measure(value, idFont).Width - 2.2f;
        }
        canvas.DrawText(name, x + 22, y, new TicketFont(63, Bold: true), Black);
    }

    private static void DrawCenteredLines(ITicketDrawingBackend canvas, IReadOnlyList<string> lines,
        TicketRect bounds, TicketFont font, float gap)
    {
        var metrics = lines.Select(line => canvas.Measure(line, font)).ToArray();
        var totalHeight = metrics.Sum(metric => metric.Height) + Math.Max(0, lines.Count - 1) * gap;
        var y = bounds.Top + (bounds.Height - totalHeight) / 2;
        for (var i = 0; i < lines.Count; i++)
        {
            canvas.DrawText(lines[i], bounds.Left + (bounds.Width - metrics[i].Width) / 2,
                y, font, Black);
            y += metrics[i].Height + gap;
        }
    }

    private static IEnumerable<TicketTextRun> SeatRuns(string value)
    {
        var normalized = value.Trim();
        var match = StandardSeat(normalized);
        if (!match.Success) match = StandardSeat(normalized + "号");
        var runs = new List<TicketTextRun>();
        if (match.Success)
        {
            AddCarriage(runs, match.Groups["car"].Value);
            AddStandardSeat(runs, match.Groups["seat"].Value);
            runs.Add(SmallLabel("号", 7));
            return runs;
        }
        var fallback = Regex.Match(normalized, @"^(?<car>\d+)\s*车\s*(?<seat>.*)$");
        var seat = normalized;
        if (fallback.Success)
        {
            AddCarriage(runs, fallback.Groups["car"].Value);
            seat = fallback.Groups["seat"].Value;
        }
        var first = true;
        foreach (Match part in Regex.Matches(seat, @"[A-Z]+|\d+|[\u3400-\u9FFF]+|.", RegexOptions.IgnoreCase))
        {
            var text = part.Value;
            var padding = first ? 9 : 0;
            if (text.All(c => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z'))
                runs.Add(new(text, new(73, TicketFontFamily.Song, true), padding, .85f));
            else if (text.All(char.IsDigit)) runs.Add(new(text, new(73, TicketFontFamily.IdCode), padding));
            else if (text.All(c => c is >= '\u3400' and <= '\u9FFF'))
                runs.Add(new(text, new(63, TicketFontFamily.Song, true), padding));
            else runs.Add(new(text, new(73, TicketFontFamily.IdCode), padding));
            first = false;
        }
        return runs;
    }

    private static Match StandardSeat(string value) => Regex.Match(value,
        @"^(?<car>\d+)\s*车\s*(?<seat>[0-9A-Z]+)\s*号$", RegexOptions.IgnoreCase);

    private static void AddCarriage(ICollection<TicketTextRun> runs, string car)
    {
        if (car == "99") return;
        runs.Add(new(car, new(73, TicketFontFamily.IdCode)));
        runs.Add(SmallLabel("车", 7));
    }

    private static void AddStandardSeat(ICollection<TicketTextRun> runs, string seat)
    {
        var first = true;
        foreach (Match part in Regex.Matches(seat, "[A-Z]+|[^A-Z]+", RegexOptions.IgnoreCase))
        {
            var letter = part.Value.All(char.IsLetter);
            runs.Add(new(part.Value, new(73, letter ? TicketFontFamily.Song : TicketFontFamily.IdCode,
                letter), first ? 9 : 0, letter ? .85f : 1));
            first = false;
        }
    }

    private static TicketTextRun SmallLabel(string text, float padding) =>
        new(text, new TicketFont(43, TicketFontFamily.IdCode, true), padding, OffsetY: 5);

    private static string Station(string value)
    {
        var station = value.Trim();
        return station.EndsWith('站') ? station[..^1] : station;
    }
}
