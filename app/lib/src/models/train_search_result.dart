class TrainSearchResult {
  const TrainSearchResult({
    required this.trainNumber,
    required this.departureStation,
    required this.arrivalStation,
    required this.trainNo,
    this.trainCodes,
    this.lookupDate,
  });

  final String trainNumber;
  final String departureStation;
  final String arrivalStation;
  final String trainNo;

  /// 库里的规范号对（如 `D111/D114`），单号车次为空。
  ///
  /// 检索结果按命中的单个号展示，同一个单号可能挂在两个号对下；按 [trainNumber]
  /// 去查站序会被服务端按固定优先级挑一个号对，未必是这一行对应的那趟车。
  /// 有它就用它。
  final String? trainCodes;

  final DateTime? lookupDate;

  /// 查站序时用的车次标识。
  String get lookupTrainNumber {
    final codes = trainCodes?.trim() ?? '';
    return codes.isEmpty ? trainNo : codes;
  }

  String get summary => '$departureStation → $arrivalStation $trainNo';

  /// 换一个展示号，其余（含查站序用的标识）不变。
  ///
  /// 号对车次拆成单个号展示时用：查站序仍按单个号走服务端解析，[trainCodes]
  /// 保留规范号对，导入/重建路径据此认车不会被拆行影响。
  TrainSearchResult withTrainNumber(String value) => TrainSearchResult(
    trainNumber: value,
    departureStation: departureStation,
    arrivalStation: arrivalStation,
    trainNo: value,
    trainCodes: trainCodes,
    lookupDate: lookupDate,
  );

  factory TrainSearchResult.fromJson(
    Map<String, dynamic> json, {
    DateTime? lookupDate,
  }) {
    return TrainSearchResult(
      trainNumber: json['station_train_code'] ?? '',
      departureStation: json['from_station'] ?? '',
      arrivalStation: json['to_station'] ?? '',
      trainNo: json['train_no'] ?? '',
      trainCodes: json['train_codes'] as String?,
      lookupDate: lookupDate,
    );
  }
}
