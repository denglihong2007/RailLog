import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';

void main() {
  test('fromJson removes whitespace from 12306 station names', () {
    final stop = TrainScheduleStop.fromJson({
      'station_name': ' 北 京\t朝 阳 ',
      'station_no': '01',
      'arrive_time': '----',
      'start_time': '08:00',
      'running_time': '00:00',
      'arrive_day_str': '当日到达',
      'arrive_day_diff': '0',
    });

    expect(stop.stationName, '北京朝阳');
  });
}
