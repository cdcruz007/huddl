/// Centralised service for managing test/demo user accounts.
///
/// These accounts can log in using the hardcoded OTP **123456**
/// without triggering a real SMS send. They also have pre-populated
/// onboarding data so the home screen loads instantly.
class TestAccountService {
  static final TestAccountService _instance = TestAccountService._internal();
  factory TestAccountService() => _instance;
  TestAccountService._internal();

  /// The universal test OTP that bypasses real SMS verification.
  static const String testOtp = '123456';

  /// Registered test phone numbers (digits only, no country code).
  /// These are the 10-digit UK mobile numbers after stripping +44.
  static const List<String> testPhoneNumbers = [
    '7575888452',
    '7575677086',
  ];

  /// Check whether [digits] (10-digit UK mobile, no country code) is a test account.
  static bool isTestAccount(String digits) {
    final normalised = _normalise(digits);
    return testPhoneNumbers.contains(normalised);
  }

  /// Check whether a full international number (+447575888452) is a test account.
  static bool isTestAccountFull(String fullNumber) {
    String stripped = fullNumber.replaceAll(RegExp(r'\s+'), '');
    if (stripped.startsWith('+44')) stripped = stripped.substring(3);
    if (stripped.startsWith('0')) stripped = stripped.substring(1);
    return isTestAccount(stripped);
  }

  /// Verify the entered OTP for a test account.
  /// Returns `true` when [code] matches the hardcoded test OTP.
  static bool verifyTestOtp(String code) => code.trim() == testOtp;

  /// Pre-populated profile data for test account 1 (7575888452).
  static Map<String, dynamic> get testProfile1 => {
        'name': 'Sarah Mitchell',
        'parentType': 'mum',
        'stagesOfLife': ['Baby (0-1)', 'Toddler (1-3)'],
        'postcode': 'CB1 2AB',
        'borough': 'Cambridge',
        'dueDate': null,
        'children': [
          {'name': 'Olivia', 'birthday': '2023-06-15'},
          {'name': 'Noah', 'birthday': '2024-11-02'},
        ],
        'phoneNumber': '7575888452',
        'countryCode': '+44',
        'bio':
            'Mum of two under 3 in Cambridge. Always looking for playgroups, soft play sessions and other parents to grab a coffee with!',
        'photoUrl': '',
        'tier': 'innerCircle',
        'isProvider': false,
      };

  /// Pre-populated profile data for test account 2 (7575677086).
  static Map<String, dynamic> get testProfile2 => {
        'name': 'James Thompson',
        'parentType': 'dad',
        'stagesOfLife': ['Expecting', 'Baby (0-1)'],
        'postcode': 'CB2 1TN',
        'borough': 'Cambridge',
        'dueDate': '2025',
        'children': [
          {'name': 'Amelia', 'birthday': '2024-08-20'},
        ],
        'phoneNumber': '7575677086',
        'countryCode': '+44',
        'bio':
            'First-time dad in Cambridge, baby girl born last summer. Looking for dad groups, baby classes and family-friendly things to do at weekends.',
        'photoUrl': '',
        'tier': 'innerCircle',
        'isProvider': false,
      };

  /// Returns the pre-populated profile for the given digits,
  /// or `null` if not a test account.
  static Map<String, dynamic>? getTestProfile(String digits) {
    final n = _normalise(digits);
    if (n == '7575888452') return testProfile1;
    if (n == '7575677086') return testProfile2;
    return null;
  }

  /// Returns the pre-populated profile for a full international number.
  static Map<String, dynamic>? getTestProfileFull(String fullNumber) {
    String stripped = fullNumber.replaceAll(RegExp(r'\s+'), '');
    if (stripped.startsWith('+44')) stripped = stripped.substring(3);
    if (stripped.startsWith('0')) stripped = stripped.substring(1);
    return getTestProfile(stripped);
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  static String _normalise(String input) {
    String raw = input.replaceAll(RegExp(r'\s+'), '');
    if (raw.startsWith('+44')) raw = raw.substring(3);
    if (raw.startsWith('0')) raw = raw.substring(1);
    return raw;
  }
}
