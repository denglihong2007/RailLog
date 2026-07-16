import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/update_service.dart';

void main() {
  test('compares stable semantic versions', () {
    expect(compareAppVersions('1.1.0', '1.0.9'), greaterThan(0));
    expect(compareAppVersions('v1.0.0', '1.0.0'), 0);
    expect(compareAppVersions('1.0.0', '1.0.0+12'), 0);
  });

  test('treats prerelease as older than stable release', () {
    expect(compareAppVersions('1.0.0-beta.1', '1.0.0'), lessThan(0));
    expect(compareAppVersions('1.0.0', '1.0.0-rc.1'), greaterThan(0));
  });
}
