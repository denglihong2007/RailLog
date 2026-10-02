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

    test('splits RZ25x models as RZ instead of matching the RZ2 prefix', () {
      final results = TrainModelParser.parse('RZ25G 1234 + rz25k 5678 + RZ2');

      expect(results.map((result) => result.prefix), ['RZ', 'RZ', 'RZ2']);
      expect(results.map((result) => result.model), ['25G', '25k', '']);
      expect(results.map((result) => result.modelCode), [
        'RZ25G',
        'RZ25k',
        'RZ2',
      ]);
      expect(results.map((result) => result.statisticsCode), [
        '25G',
        '25k',
        '',
      ]);
      expect(results[0].numbers, ['1234']);
      expect(results[1].numbers, ['5678']);
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

    test('splits formations on slashes and counts every model once', () {
      final results = TrainModelParser.parse(
        'HXD1D 0563+25T/HXD1D 0100+25T/NJ2 0071+HXN3 0331+25G',
      );

      expect(results.map((result) => result.model), [
        'HXD1D',
        '25T',
        'NJ2',
        'HXN3',
        '25G',
      ]);
      expect(results[0].category, TrainCategory.locomotive);
      expect(results[0].numbers, ['0563', '0100']);
      expect(results[1].category, TrainCategory.coach);
      expect(results[1].statisticsCode, '25T');
      expect(results[1].numbers, isEmpty);
    });

    test('keeps formations separate for display', () {
      final formations = TrainModelParser.parseFormations(
        'HXD1D 0563+25T/HXD1D 0100+25T/NJ2 0071+HXN3 0331+25G',
      );

      expect(formations, hasLength(3));
      expect(formations.map((f) => f.segments.length), [2, 2, 3]);
      expect(formations[0].segments.map((s) => s.model), ['HXD1D', '25T']);
      expect(formations[0].segments.first.numbers, ['0563']);
      expect(formations[1].segments.first.numbers, ['0100']);
      expect(formations[2].segments.map((s) => s.model), [
        'NJ2',
        'HXN3',
        '25G',
      ]);
    });

    test('counts a coupled EMU model once', () {
      final result = TrainModelParser.parse('CRH380B-0001&0002').single;

      expect(result.category, TrainCategory.emu);
      expect(result.modelCode, 'CRH380B');
      expect(result.numbers, ['0001', '0002']);
    });

    test('merges one model across formations but keeps them split for display', () {
      final merged = TrainModelParser.parse('CRH380B-0001/CRH380B-0002').single;

      expect(merged.modelCode, 'CRH380B');
      expect(merged.numbers, ['0001', '0002']);

      final formations = TrainModelParser.parseFormations(
        'CRH380B-0001/CRH380B-0002',
      );
      expect(formations, hasLength(2));
      expect(formations[0].segments.single.numbers, ['0001']);
      expect(formations[1].segments.single.numbers, ['0002']);
    });

    test('ignores empty formations', () {
      expect(TrainModelParser.parseFormations('//'), isEmpty);
      expect(TrainModelParser.parseFormations('HXD1D 0001/'), hasLength(1));
      expect(
        TrainModelParser.parseFormations(
          'HXD1D 0001//25T',
        ).map((f) => f.segments.length),
        [1, 1],
      );
    });
  });
}
