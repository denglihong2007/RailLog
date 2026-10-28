namespace RailLog.API.Services;

public sealed class AnnouncementOptions
{
    public string[] Items { get; init; } = [
        "Z旋转就是N，N去掉一竖就是V！",
        "线路数据库已经更新！",
        "现已支持使用“设置”中的批量工具补全列车到点！",
        "RailLog永远保持免费且开源！"];
    public int Weight { get; init; } = 10;
}
