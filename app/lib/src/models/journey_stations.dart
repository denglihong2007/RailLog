/// 一次行程按顺序经过的经停站，以及每一站间段所属的线路名。
///
/// 站点序列决定地图上要画哪些段，线路名则用来查这些段的真实轨道折线
/// （见 RailTrackService）。两者必须一起传递：只给站名就无法知道相邻两站
/// 之间走的是哪条线，也就查不到折线。
///
/// [legRouteNames] 与站点序列错一位：第 i 项是 `stations[i] → stations[i+1]`
/// 所属的线路名。某项为空字符串表示该段未能归属到具体线路，绘制时回退为直线。
class JourneyStations {
  const JourneyStations({required this.stations, this.legRouteNames = const []});

  /// 只有站名、没有线路信息时的退化形式。绘制结果是站间直线（历史行为）。
  const JourneyStations.of(this.stations) : legRouteNames = const [];

  final List<String> stations;
  final List<String> legRouteNames;

  /// 第 [index] 段的线路名；越界或未标注时返回空字符串。
  String routeNameForLeg(int index) =>
      index >= 0 && index < legRouteNames.length ? legRouteNames[index] : '';
}
