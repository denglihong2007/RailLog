enum TrainCategory { emu, coach, locomotive }

class TrainModelParseResult {
  const TrainModelParseResult({
    required this.rawSegment,
    required this.category,
    required this.prefix,
    required this.model,
    required this.numbers,
  });

  final String rawSegment;
  final TrainCategory category;
  final String prefix;
  final String model;
  final List<String> numbers;

  String get modelCode => '$prefix$model';

  String get statisticsCode =>
      category == TrainCategory.coach ? model : modelCode;
}

class TrainModelParser {
  const TrainModelParser._();

  static const List<String> _sortedPrefixes = [
    'SYZ',
    'SYW',
    'SRZ',
    'SRW',
    'GRW',
    'RZT',
    'RZ1',
    'RZ2',
    'YZ',
    'YW',
    'RZ',
    'RW',
    'KD',
    'WX',
  ];

  static List<TrainModelParseResult> parse(String? input) {
    final source = input?.trim() ?? '';
    if (source.isEmpty) return const [];

    final resultsByKey = <String, TrainModelParseResult>{};
    final orderedKeys = <String>[];
    for (final rawPart in source.split('+')) {
      final segment = rawPart.trim();
      if (segment.isEmpty) continue;

      late final TrainCategory category;
      var prefix = '';
      late final String model;
      late final List<String> numbers;

      if (_startsWithIgnoreCase(segment, 'MTR') ||
          _startsWithIgnoreCase(segment, 'CR') ||
          _startsWithIgnoreCase(segment, 'LCR') ||
          _startsWithIgnoreCase(segment, 'CJ')) {
        category = TrainCategory.emu;
        final parsed = _parseEmuSegment(segment);
        model = parsed.$1;
        numbers = parsed.$2;
      } else {
        final parsed = _parseLocoOrCoachSegment(segment);
        category = parsed.$1;
        prefix = parsed.$2;
        model = parsed.$3;
        numbers = parsed.$4;
      }

      final key = '${category.name}_${prefix}_$model'.toLowerCase();
      final existing = resultsByKey[key];
      if (existing == null) {
        resultsByKey[key] = TrainModelParseResult(
          rawSegment: segment,
          category: category,
          prefix: prefix,
          model: model,
          numbers: List.unmodifiable(numbers),
        );
        orderedKeys.add(key);
        continue;
      }

      final mergedNumbers = [...existing.numbers];
      for (final number in numbers) {
        if (!mergedNumbers.any(
          (existingNumber) =>
              existingNumber.toLowerCase() == number.toLowerCase(),
        )) {
          mergedNumbers.add(number);
        }
      }
      resultsByKey[key] = TrainModelParseResult(
        rawSegment: existing.rawSegment,
        category: existing.category,
        prefix: existing.prefix,
        model: existing.model,
        numbers: List.unmodifiable(mergedNumbers),
      );
    }
    return List.unmodifiable(orderedKeys.map((key) => resultsByKey[key]!));
  }

  static bool containsEmu(String? input) =>
      parse(input).any((parsed) => parsed.category == TrainCategory.emu);

  static (String, List<String>) _parseEmuSegment(String segment) {
    final lastAmpersand = segment.lastIndexOf('&');
    final searchEnd = lastAmpersand >= 0 ? lastAmpersand : segment.length;
    var numberStart = searchEnd;

    while (numberStart > 0) {
      final character = segment[numberStart - 1];
      if (!_isDigit(character) && character != '&') break;
      numberStart--;
    }

    if (numberStart > 0 && numberStart < segment.length) {
      final separator = segment[numberStart - 1];
      if (separator == '-' || separator == ' ') {
        return (
          segment.substring(0, numberStart - 1),
          _parseNumbers(segment.substring(numberStart)),
        );
      }
    }

    return (segment, const []);
  }

  static (TrainCategory, String, String, List<String>) _parseLocoOrCoachSegment(
    String segment,
  ) {
    final spaceIndex = segment.indexOf(' ');
    final modelPart =
        (spaceIndex >= 0 ? segment.substring(0, spaceIndex) : segment).trim();
    final numberPart =
        (spaceIndex >= 0 ? segment.substring(spaceIndex + 1) : '').trim();
    final numbers = numberPart.isEmpty ? <String>[] : _parseNumbers(numberPart);

    for (final prefix in _sortedPrefixes) {
      if (_startsWithIgnoreCase(modelPart, prefix)) {
        return (
          TrainCategory.coach,
          prefix,
          modelPart.substring(prefix.length),
          numbers,
        );
      }
    }

    final category =
        modelPart.toUpperCase().contains('M1') ||
            (_hasTwoContinuousDigits(modelPart) &&
                !modelPart.toUpperCase().contains('DF'))
        ? TrainCategory.coach
        : TrainCategory.locomotive;
    return (category, '', modelPart, numbers);
  }

  static List<String> _parseNumbers(String value) {
    final numbers = <String>[];
    for (final part in value.split('&')) {
      final number = part.trim();
      if (number.isEmpty ||
          numbers.any(
            (existing) => existing.toLowerCase() == number.toLowerCase(),
          )) {
        continue;
      }
      numbers.add(number);
    }
    return numbers;
  }

  static bool _startsWithIgnoreCase(String value, String prefix) {
    if (value.length < prefix.length) return false;
    return value.substring(0, prefix.length).toUpperCase() == prefix;
  }

  static bool _hasTwoContinuousDigits(String value) {
    for (var i = 0; i < value.length - 1; i++) {
      if (_isDigit(value[i]) && _isDigit(value[i + 1])) return true;
    }
    return false;
  }

  static bool _isDigit(String value) {
    final codeUnit = value.codeUnitAt(0);
    return codeUnit >= 0x30 && codeUnit <= 0x39;
  }
}
