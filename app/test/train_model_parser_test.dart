import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_model_parser.dart';

void main() {
  group('TrainModelParser', () {
    test('parses mixed train model segments', () {
      final results = TrainModelParser.parse(
        ' CR400BF-5033&5034 + YZ25G 1234&5678 + HXD1D 0001 + DF11 0123 ',
      );

      expect(results, hasLength(4));

      expect(results[0].category, TrainCategory.emu);
      expect(results[0].rawSegment, 'CR400BF-5033&5034');
      expect(results[0].prefix, isEmpty);
      expect(results[0].model, 'CR400BF');
      expect(results[0].numbers, ['5033', '5034']);
      expect(results[0].modelCode, 'CR400BF');
      expect(results[0].statisticsCode, 'CR400BF');

      expect(results[1].category, TrainCategory.coach);
      expect(results[1].prefix, 'YZ');
      expect(results[1].model, '25G');
      expect(results[1].numbers, ['1234', '5678']);
      expect(results[1].modelCode, 'YZ25G');
      expect(results[1].statisticsCode, '25G');

      expect(results[2].category, TrainCategory.locomotive);
      expect(results[2].model, 'HXD1D');
      expect(results[2].numbers, ['0001']);

      expect(results[3].category, TrainCategory.locomotive);
      expect(results[3].model, 'DF11');
      expect(results[3].numbers, ['0123']);
    });

    test('recognizes MTR, CR, CJ, and LCR prefixes as EMU models', () {
      final results = TrainModelParser.parse(
        'mtr-1234+cr400af 2001+cj2-3456+lcr-7890',
      );

      expect(results.map((result) => result.category), [
        TrainCategory.emu,
        TrainCategory.emu,
        TrainCategory.emu,
        TrainCategory.emu,
      ]);
      expect(results.map((result) => result.model), [
        'mtr',
        'cr400af',
        'cj2',
        'lcr',
      ]);
      expect(results.map((result) => result.numbers), [
        ['1234'],
        ['2001'],
        ['3456'],
        ['7890'],
      ]);
    });

    test('splits known coach prefixes before detecting model numbers', () {
      final results = TrainModelParser.parse('YW25T 1234+RW19T 5678');

      expect(results.map((result) => result.category), [
        TrainCategory.coach,
        TrainCategory.coach,
      ]);
      expect(results.map((result) => result.prefix), ['YW', 'RW']);
      expect(results.map((result) => result.model), ['25T', '19T']);
      expect(results.map((result) => result.modelCode), ['YW25T', 'RW19T']);
      expect(results.map((result) => result.statisticsCode), ['25T', '19T']);
    });

    test('uses the reference fallback for unlisted prefixes', () {
      final results = TrainModelParser.parse(
        '25G 1234+SS8 0001+DF4B 0002+M1A 0003',
      );

      expect(results.map((result) => result.category), [
        TrainCategory.coach,
        TrainCategory.locomotive,
        TrainCategory.locomotive,
        TrainCategory.coach,
      ]);
      expect(results.map((result) => result.model), [
        '25G',
        'SS8',
        'DF4B',
        'M1A',
      ]);
    });

    test(
      'treats a model without a separator and numbers as the full model',
      () {
        final result = TrainModelParser.parse('CR400BF').single;

        expect(result.category, TrainCategory.emu);
        expect(result.model, 'CR400BF');
        expect(result.numbers, isEmpty);
      },
    );

    test('ignores empty segments and empty input', () {
      expect(TrainModelParser.parse('++  +'), isEmpty);
      expect(TrainModelParser.parse(null), isEmpty);
      expect(TrainModelParser.parse('   '), isEmpty);
    });

    test('merges matching models and deduplicates their numbers', () {
      final result = TrainModelParser.parse(
        'CR400BF-5033&5034 + cr400bf 5035&5033',
      ).single;

      expect(result.rawSegment, 'CR400BF-5033&5034');
      expect(result.category, TrainCategory.emu);
      expect(result.model, 'CR400BF');
      expect(result.numbers, ['5033', '5034', '5035']);
    });

    test('containsEmu detects whether any segment is an EMU', () {
      expect(TrainModelParser.containsEmu('HXD1D 0001'), isFalse);
      expect(TrainModelParser.containsEmu('HXD1D 0001+CR400BF-5033'), isTrue);
      expect(TrainModelParser.containsEmu('CJ2-3456'), isTrue);
    });
  });
}
