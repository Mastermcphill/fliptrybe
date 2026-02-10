import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/constants/ng_states.dart';

void main() {
  test('Nigeria states list has 37 entries including FCT', () {
    expect(nigeriaStates.length, 37);
    expect(nigeriaStates.contains('Federal Capital Territory'), isTrue);
  });
}
