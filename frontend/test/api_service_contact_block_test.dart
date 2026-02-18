import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/api_service.dart';

void main() {
  test('ApiService detects contact blocked payloads', () {
    expect(ApiService.isContactBlocked({'error': 'CONTACT_BLOCKED'}), isTrue);
    expect(
      ApiService.isContactBlocked({
        'error': 'DESCRIPTION_CONTACT_BLOCKED',
      }),
      isTrue,
    );
    expect(
      ApiService.isContactBlocked(
        'For safety, contact details cannot be shared in chat.',
      ),
      isTrue,
    );
    expect(ApiService.isContactBlocked({'error': 'OTHER'}), isFalse);
  });
}

