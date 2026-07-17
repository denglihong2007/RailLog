import 'package:raillog/src/models/dashboard_trip_entry.dart';

enum DashboardAchievementKind {
  freeMeal,
  overnightSeat,
  tightTransfer,
  sevenDayStreak,
  thirtyDayStreak,
  yearStreak,
  duration24Hours,
  duration48Hours,
  duration72Hours,
  all25Series,
  allEmuSeries,
  allSeatTypes,
  noSeat12Hours,
  hundredTickets,
  midnightBoarding,
  wallFacingSeat,
  hundredStations,
  thousandKilometers,
  airRail,
  railFerry,
  hundredThousandKilometers,
  fTrain,
  axleOverheat,
  advantageIsMine,
  platformSubsidence,
  archaeologyTeam,
  strategist,
  eveOfTheStorm,
}

class DashboardAchievement {
  const DashboardAchievement({
    required this.kind,
    required this.title,
    required this.requirement,
    this.unlockedBy,
  });

  final DashboardAchievementKind kind;
  final String title;
  final String requirement;
  final DashboardTripEntry? unlockedBy;

  bool get isUnlocked => unlockedBy != null;
}
