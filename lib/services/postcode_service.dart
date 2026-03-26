import 'package:flutter/foundation.dart';

class PostcodeService {
  static final PostcodeService _instance = PostcodeService._internal();
  factory PostcodeService() => _instance;
  PostcodeService._internal();

  // UK Borough mapping based on postcode prefixes
  final Map<String, String> _postcodeToBorough = {
    // London Boroughs
    // City of London (EC postcodes)
    'EC1': 'City of London',
    'EC1A': 'City of London',
    'EC1M': 'Islington',
    'EC1N': 'Camden',
    'EC1R': 'Islington',
    'EC1V': 'Islington',
    'EC1Y': 'Islington',
    'EC2': 'City of London',
    'EC2A': 'City of London',
    'EC2M': 'City of London',
    'EC2N': 'City of London',
    'EC2R': 'City of London',
    'EC2V': 'City of London',
    'EC2Y': 'City of London',
    'EC3': 'City of London',
    'EC3A': 'City of London',
    'EC3M': 'City of London',
    'EC3N': 'City of London',
    'EC3P': 'City of London',
    'EC3R': 'City of London',
    'EC3V': 'City of London',
    'EC4': 'City of London',
    'EC4A': 'City of London',
    'EC4M': 'City of London',
    'EC4N': 'City of London',
    'EC4P': 'City of London',
    'EC4R': 'City of London',
    'EC4V': 'City of London',
    'EC4Y': 'City of London',
    
    // East London
    'E1': 'Tower Hamlets',
    'E2': 'Tower Hamlets',
    'E3': 'Tower Hamlets',
    'E4': 'Waltham Forest',
    'E5': 'Hackney',
    'E6': 'Newham',
    'E7': 'Newham',
    'E8': 'Hackney',
    'E9': 'Hackney',
    'E10': 'Waltham Forest',
    'E11': 'Redbridge',
    'E12': 'Newham',
    'E13': 'Newham',
    'E14': 'Tower Hamlets',
    'E15': 'Newham',
    'E16': 'Newham',
    'E17': 'Waltham Forest',
    'E18': 'Redbridge',
    
    'N1': 'Islington',
    'N2': 'Barnet',
    'N3': 'Barnet',
    'N4': 'Hackney',
    'N5': 'Islington',
    'N6': 'Camden',
    'N7': 'Islington',
    'N8': 'Haringey',
    'N9': 'Enfield',
    'N10': 'Haringey',
    'N11': 'Enfield',
    'N12': 'Barnet',
    'N13': 'Enfield',
    'N14': 'Enfield',
    'N15': 'Haringey',
    'N16': 'Hackney',
    'N17': 'Haringey',
    'N18': 'Enfield',
    'N19': 'Islington',
    'N20': 'Barnet',
    'N21': 'Enfield',
    'N22': 'Haringey',
    
    'NW1': 'Camden',
    'NW2': 'Barnet',
    'NW3': 'Camden',
    'NW4': 'Barnet',
    'NW5': 'Camden',
    'NW6': 'Camden',
    'NW7': 'Barnet',
    'NW8': 'Westminster',
    'NW9': 'Barnet',
    'NW10': 'Brent',
    'NW11': 'Barnet',
    
    'SE1': 'Southwark',
    'SE2': 'Greenwich',
    'SE3': 'Greenwich',
    'SE4': 'Lewisham',
    'SE5': 'Southwark',
    'SE6': 'Lewisham',
    'SE7': 'Greenwich',
    'SE8': 'Lewisham',
    'SE9': 'Greenwich',
    'SE10': 'Greenwich',
    'SE11': 'Lambeth',
    'SE12': 'Lewisham',
    'SE13': 'Lewisham',
    'SE14': 'Lewisham',
    'SE15': 'Southwark',
    'SE16': 'Southwark',
    'SE17': 'Southwark',
    'SE18': 'Greenwich',
    'SE19': 'Croydon',
    'SE20': 'Bromley',
    'SE21': 'Southwark',
    'SE22': 'Southwark',
    'SE23': 'Lewisham',
    'SE24': 'Lambeth',
    'SE25': 'Croydon',
    'SE26': 'Lewisham',
    'SE27': 'Lambeth',
    'SE28': 'Greenwich',
    
    'SW1': 'Westminster',
    'SW1A': 'Westminster',  // Special central London postcode
    'SW1P': 'Westminster',  // Special central London postcode
    'SW1V': 'Westminster',  // Special central London postcode
    'SW1W': 'Westminster',  // Special central London postcode
    'SW1X': 'Westminster',  // Special central London postcode
    'SW1Y': 'Westminster',  // Special central London postcode,
    'SW2': 'Lambeth',
    'SW3': 'Kensington and Chelsea',
    'SW4': 'Lambeth',
    'SW5': 'Kensington and Chelsea',
    'SW6': 'Hammersmith and Fulham',
    'SW7': 'Kensington and Chelsea',
    'SW8': 'Lambeth',
    'SW9': 'Lambeth',
    'SW10': 'Kensington and Chelsea',
    'SW11': 'Wandsworth',
    'SW12': 'Wandsworth',
    'SW13': 'Richmond',
    'SW14': 'Richmond',
    'SW15': 'Wandsworth',
    'SW16': 'Lambeth',
    'SW17': 'Wandsworth',
    'SW18': 'Wandsworth',
    'SW19': 'Merton',
    'SW20': 'Merton',
    
    'W1': 'Westminster',
    'W1A': 'Westminster',  // Oxford Street, BBC
    'W1B': 'Westminster',
    'W1C': 'Westminster',
    'W1D': 'Westminster',
    'W1F': 'Westminster',
    'W1G': 'Westminster',
    'W1H': 'Westminster',
    'W1J': 'Westminster',
    'W1K': 'Westminster',
    'W1S': 'Westminster',
    'W1T': 'Westminster',
    'W1U': 'Westminster',
    'W1W': 'Westminster',
    'W2': 'Westminster',
    'W3': 'Ealing',
    'W4': 'Hounslow',
    'W5': 'Ealing',
    'W6': 'Hammersmith and Fulham',
    'W7': 'Ealing',
    'W8': 'Kensington and Chelsea',
    'W9': 'Westminster',
    'W10': 'Kensington and Chelsea',
    'W11': 'Kensington and Chelsea',
    'W12': 'Hammersmith and Fulham',
    'W13': 'Ealing',
    'W14': 'Hammersmith and Fulham',
    
    // Central London (WC postcodes)
    'WC1': 'Camden',
    'WC1A': 'Camden',
    'WC1B': 'Camden',
    'WC1E': 'Camden',
    'WC1H': 'Camden',
    'WC1N': 'Camden',
    'WC1R': 'Camden',
    'WC1V': 'Camden',
    'WC1X': 'Camden',
    'WC2': 'Westminster',
    'WC2A': 'Westminster',
    'WC2B': 'Westminster',
    'WC2E': 'Westminster',
    'WC2H': 'Westminster',
    'WC2N': 'Westminster',
    'WC2R': 'Westminster',
    
    // Cambridge
    'CB1': 'Cambridge',
    'CB2': 'Cambridge',
    'CB3': 'Cambridge',
    'CB4': 'Cambridge',
    'CB5': 'Cambridge',
    'CB21': 'South Cambridgeshire',
    'CB22': 'South Cambridgeshire',
    'CB23': 'South Cambridgeshire',
    'CB24': 'South Cambridgeshire',
    'CB25': 'East Cambridgeshire',
    
    // Manchester
    'M1': 'Manchester',
    'M2': 'Manchester',
    'M3': 'Manchester',
    'M4': 'Manchester',
    'M5': 'Salford',
    'M6': 'Salford',
    'M7': 'Salford',
    'M8': 'Manchester',
    'M9': 'Manchester',
    'M11': 'Manchester',
    'M12': 'Manchester',
    'M13': 'Manchester',
    'M14': 'Manchester',
    'M15': 'Manchester',
    'M16': 'Trafford',
    'M17': 'Trafford',
    'M18': 'Manchester',
    'M19': 'Manchester',
    'M20': 'Manchester',
    'M21': 'Manchester',
    'M22': 'Manchester',
    'M23': 'Manchester',
    
    // Birmingham
    'B1': 'Birmingham',
    'B2': 'Birmingham',
    'B3': 'Birmingham',
    'B4': 'Birmingham',
    'B5': 'Birmingham',
    'B6': 'Birmingham',
    'B7': 'Birmingham',
    'B8': 'Birmingham',
    'B9': 'Birmingham',
    'B10': 'Birmingham',
    'B11': 'Birmingham',
    'B12': 'Birmingham',
    'B13': 'Birmingham',
    'B14': 'Birmingham',
    'B15': 'Birmingham',
    'B16': 'Birmingham',
    'B17': 'Birmingham',
    'B18': 'Birmingham',
    'B19': 'Birmingham',
    'B20': 'Birmingham',
    'B21': 'Birmingham',
    
    // Leeds
    'LS1': 'Leeds',
    'LS2': 'Leeds',
    'LS3': 'Leeds',
    'LS4': 'Leeds',
    'LS5': 'Leeds',
    'LS6': 'Leeds',
    'LS7': 'Leeds',
    'LS8': 'Leeds',
    'LS9': 'Leeds',
    'LS10': 'Leeds',
    'LS11': 'Leeds',
    'LS12': 'Leeds',
    'LS13': 'Leeds',
    'LS14': 'Leeds',
    'LS15': 'Leeds',
    'LS16': 'Leeds',
    'LS17': 'Leeds',
    
    // Bristol
    'BS1': 'Bristol',
    'BS2': 'Bristol',
    'BS3': 'Bristol',
    'BS4': 'Bristol',
    'BS5': 'Bristol',
    'BS6': 'Bristol',
    'BS7': 'Bristol',
    'BS8': 'Bristol',
    'BS9': 'Bristol',
    'BS10': 'Bristol',
    'BS11': 'Bristol',
    'BS13': 'Bristol',
    'BS14': 'Bristol',
    'BS15': 'Bristol',
    'BS16': 'Bristol',
  };

  /// Extract borough from postcode
  String? getBoroughFromPostcode(String? postcode) {
    if (postcode == null || postcode.isEmpty) {
      _log('No postcode provided');
      return null;
    }

    // Clean the postcode (remove spaces, uppercase)
    final cleanPostcode = postcode.replaceAll(' ', '').toUpperCase();
    
    // Extract the outward code (the part before the space in a formatted postcode)
    // UK postcodes have format: Area(1-2 letters) + District(1-2 digits/chars) + Sector(1 digit) + Unit(2 letters)
    // Examples: E1 8GG -> outward code is "E1", SW1A 1AA -> "SW1A"
    // We need to extract just the Area + District part
    
    String? outwardCode = _extractOutwardCode(cleanPostcode);
    
    if (outwardCode != null) {
      _log('Extracted outward code: $outwardCode from $postcode');
      
      // Look up the outward code in our mapping
      if (_postcodeToBorough.containsKey(outwardCode)) {
        final borough = _postcodeToBorough[outwardCode]!;
        _log('Postcode $postcode -> Borough: $borough');
        return borough;
      }
    }

    _log('Borough not found for postcode: $postcode (outward code: $outwardCode)');
    return 'Unknown Borough';
  }
  
  /// Extract the outward code from a UK postcode
  /// E1 8GG -> E1 (not E18!)
  /// E18 5NF -> E18
  /// SW1A 1AA -> SW1A
  /// CB1 2AB -> CB1
  String? _extractOutwardCode(String cleanPostcode) {
    // UK postcode format: Outward code (2-4 chars) + Inward code (always 3 chars: 1 digit + 2 letters)
    // Examples:
    //   E1 8GG  -> E18GG  -> Outward: E1  (1 letter + 1 digit)
    //   E18 5NF -> E185NF -> Outward: E18 (1 letter + 2 digits)
    //   SW1A 1AA -> SW1A1AA -> Outward: SW1A (2 letters + 1 digit + 1 letter)
    //   CB1 2AB -> CB12AB -> Outward: CB1 (2 letters + 1 digit)
    
    if (cleanPostcode.length < 5 || cleanPostcode.length > 7) {
      return null; // Invalid postcode length
    }
    
    // Match pattern: [Area: 1-2 letters][District: 1-2 digits][Optional sub-district letter][Sector digit][Unit: 2 letters]
    // We want everything before the sector digit
    final postcodePattern = RegExp(r'^([A-Z]{1,2}\d{1,2}[A-Z]?)\d[A-Z]{2}$');
    final match = postcodePattern.firstMatch(cleanPostcode);
    
    if (match != null) {
      return match.group(1); // Returns the outward code
    }
    
    return null;
  }

  /// Get list of all boroughs
  List<String> getAllBoroughs() {
    return _postcodeToBorough.values.toSet().toList()..sort();
  }

  /// Returns true if the postcode is in the Cambridge launch area.
  /// Cambridge postcodes: CB1–CB5 (city), CB21–CB25 (surrounding villages).
  /// These are the only areas supported at launch.
  bool isCambridgePostcode(String? postcode) {
    if (postcode == null || postcode.isEmpty) return false;
    final outward = _extractOutwardCode(
        postcode.replaceAll(' ', '').toUpperCase()) ?? '';
    // CB1-CB5 = Cambridge city; CB21-CB25 = South/East Cambridgeshire villages
    return outward == 'CB1' ||
        outward == 'CB2' ||
        outward == 'CB3' ||
        outward == 'CB4' ||
        outward == 'CB5' ||
        outward == 'CB21' ||
        outward == 'CB22' ||
        outward == 'CB23' ||
        outward == 'CB24' ||
        outward == 'CB25';
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('📍 PostcodeService: $message');
    }
  }
}
