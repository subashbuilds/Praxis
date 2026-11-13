import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/workspace/preview_tab.dart';

void main() {
  test('desktop preview fits a 1280px page to the device width', () {
    expect(desktopPreviewScale(412), closeTo(412 / 1280, 0.0001));
    expect(desktopPreviewScale(360), closeTo(360 / 1280, 0.0001));
    expect(desktopPreviewScale(1280), 1);
    expect(desktopPreviewScale(1440), 1);
    expect(desktopPreviewScale(0), 1);
  });
}
