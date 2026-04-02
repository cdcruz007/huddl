import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'browser_storage.dart';

class OnboardingDataService {
  static final OnboardingDataService _instance = OnboardingDataService._internal();
  factory OnboardingDataService() => _instance;
  OnboardingDataService._internal();
  
  static const String _storageKey = 'onboarding_data_v1';
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  // User onboarding data
  String? _name;
  String? _parentType; // 'mum' or 'dad'
  List<String> _stagesOfLife = [];
  String? _postcode;
  String? _dueDate;
  List<Map<String, String>> _children = []; // List of children with name and birthday
  String? _phoneNumber;
  String? _countryCode;
  String? _password;
  bool _isPhoneVerified = false;
  String? _profilePhotoPath; // local file path or web file name
  String? _bio; // "About you" free-text from onboarding
  String? _profilePhotoObjectUrl; // Web Object URL for display (blob:...)
  String? _previousPostcode; // Previous postcode before a change
  String? _previousBorough; // Previous borough (derived from previous postcode)
  int _assignedGroupCount = 0; // Number of groups assigned during onboarding

  // ── Provider-specific fields ──────────────────────────────────────────────
  List<String> _serviceTypes = [];      // e.g. ['doula', 'babysitter']
  String? _businessName;                // Display name for their service
  String? _qualifications;              // Free-text qualifications
  bool _hasDBS = false;                 // DBS checked
  String? _experience;                  // Years / description of experience
  String? _hourlyRate;                  // e.g. '15-25'
  List<String> _serviceAreas = [];      // Postcodes they cover

  // Getters
  String? get name => _name;
  String? get parentType => _parentType;
  List<String> get stagesOfLife => _stagesOfLife;
  String? get postcode => _postcode;
  String? get dueDate => _dueDate;
  List<Map<String, String>> get children => _children;
  String? get childName => _children.isNotEmpty ? _children.first['name'] : null;
  String? get childBirthday => _children.isNotEmpty ? _children.first['birthday'] : null;
  String? get phoneNumber => _phoneNumber;
  String? get countryCode => _countryCode;
  String? get fullPhoneNumber => _countryCode != null && _phoneNumber != null 
      ? '$_countryCode$_phoneNumber' 
      : null;
  String? get password => _password;
  bool get isPhoneVerified => _isPhoneVerified;
  String? get profilePhotoPath => _profilePhotoPath;
  String? get bio => _bio;
  String? get profilePhotoObjectUrl => _profilePhotoObjectUrl;
  String? get previousPostcode => _previousPostcode;
  String? get previousBorough => _previousBorough;
  int get assignedGroupCount => _assignedGroupCount;

  /// Whether the user has changed their postcode (moved to a different borough)
  bool get hasChangedBorough => _previousBorough != null && _previousBorough!.isNotEmpty;

  // Provider getters
  List<String> get serviceTypes => _serviceTypes;
  String? get businessName => _businessName;
  String? get qualifications => _qualifications;
  bool get hasDBS => _hasDBS;
  String? get experience => _experience;
  String? get hourlyRate => _hourlyRate;
  List<String> get serviceAreas => _serviceAreas;
  bool get isProvider => _parentType == 'provider';

  // Setters
  void setName(String name) {
    _name = name;
    _log('Name set: $name');
    _saveToStorage();
  }

  void setParentType(String type) {
    _parentType = type;
    _log('Parent type set: $type');
    _saveToStorage();
  }

  void setStagesOfLife(List<String> stages) {
    _stagesOfLife = stages;
    _log('Stages of life set: $stages');
    _saveToStorage();
  }

  void setPostcode(String postcode) {
    // If we already have a postcode and it's different, record the old one
    if (_postcode != null && _postcode != postcode && _postcode!.isNotEmpty) {
      _previousPostcode = _postcode;
      _log('Previous postcode saved: $_previousPostcode');
    }
    _postcode = postcode;
    _log('Postcode set: $postcode');
    _saveToStorage();
  }

  /// Explicitly set the previous borough (called when borough is resolved from previous postcode)
  void setPreviousBorough(String borough) {
    _previousBorough = borough;
    _log('Previous borough set: $borough');
    _saveToStorage();
  }

  void setDueDate(String dueDate) {
    _dueDate = dueDate;
    _log('Due date set: $dueDate');
    _saveToStorage();
  }

  void setChildInfo(String name, String birthday) {
    _children.add({'name': name, 'birthday': birthday});
    _log('Child info added - Name: $name, Birthday: $birthday');
    _saveToStorage();
  }

  void setChildren(List<Map<String, String>> children) {
    _children = children;
    _log('Children set: ${children.length} children');
    _saveToStorage();
  }

  void setPhoneNumber(String phone, {String countryCode = '+44'}) {
    _phoneNumber = phone;
    _countryCode = countryCode;
    _log('Phone number set: $countryCode$phone');
    _saveToStorage();
  }

  void setPassword(String password) {
    _password = password;
    _log('Password set (length: ${password.length})');
    _saveToStorage();
  }

  void setPhoneVerified(bool verified) {
    _isPhoneVerified = verified;
    _log('Phone verified status: $verified');
    _saveToStorage();
  }

  void setProfilePhotoPath(String? path) {
    _profilePhotoPath = path;
    _log('Profile photo path set: $path');
    _saveToStorage();
  }

  void setBio(String? bio) {
    _bio = bio;
    _log('Bio set: ${bio?.substring(0, bio.length > 30 ? 30 : bio.length)}...');
    _saveToStorage();
  }

  void setAssignedGroupCount(int count) {
    _assignedGroupCount = count;
    _log('Assigned group count set: $count');
    _saveToStorage();
  }

  void setProfilePhotoObjectUrl(String? url) {
    _profilePhotoObjectUrl = url;
    _log('Profile photo Object URL set: ${url != null ? "(blob url)" : "null"}');
    _saveToStorage();
  }

  // ── Provider setters ──────────────────────────────────────────────────────
  void setServiceTypes(List<String> types) {
    _serviceTypes = types;
    _log('Service types set: $types');
    _saveToStorage();
  }

  void setBusinessName(String? name) {
    _businessName = name;
    _log('Business name set: $name');
    _saveToStorage();
  }

  void setQualifications(String? quals) {
    _qualifications = quals;
    _log('Qualifications set: ${quals?.length ?? 0} chars');
    _saveToStorage();
  }

  void setHasDBS(bool dbs) {
    _hasDBS = dbs;
    _log('DBS checked: $dbs');
    _saveToStorage();
  }

  void setExperience(String? exp) {
    _experience = exp;
    _log('Experience set: $exp');
    _saveToStorage();
  }

  void setHourlyRate(String? rate) {
    _hourlyRate = rate;
    _log('Hourly rate set: $rate');
    _saveToStorage();
  }

  void setServiceAreas(List<String> areas) {
    _serviceAreas = areas;
    _log('Service areas set: $areas');
    _saveToStorage();
  }

  // Check if user data is complete
  bool isComplete() {
    return _name != null &&
           _parentType != null &&
           _stagesOfLife.isNotEmpty &&
           _postcode != null &&
           _phoneNumber != null &&
           _password != null &&
           _isPhoneVerified;
  }

  // Get completion percentage
  double getCompletionPercentage() {
    int completed = 0;
    int total = 7; // Total required fields

    if (_name != null) completed++;
    if (_parentType != null) completed++;
    if (_stagesOfLife.isNotEmpty) completed++;
    if (_postcode != null) completed++;
    if (_phoneNumber != null) completed++;
    if (_password != null) completed++;
    if (_isPhoneVerified) completed++;

    return (completed / total) * 100;
  }

  // Get user data as Map
  Map<String, dynamic> toMap() {
    return {
      'name': _name,
      'parent_type': _parentType,
      'stages_of_life': _stagesOfLife,
      'postcode': _postcode,
      'due_date': _dueDate,
      'children': _children,
      'phone_number': fullPhoneNumber,
      'is_phone_verified': _isPhoneVerified,
      'completion_percentage': getCompletionPercentage(),
    };
  }

  // Clear all data
  void clear() async {
    _name = null;
    _parentType = null;
    _stagesOfLife = [];
    _postcode = null;
    _dueDate = null;
    _children = [];
    _phoneNumber = null;
    _countryCode = null;
    _password = null;
    _isPhoneVerified = false;
    _profilePhotoPath = null;
    _bio = null;
    _profilePhotoObjectUrl = null;
    _previousPostcode = null;
    _previousBorough = null;
    _assignedGroupCount = 0;
    _serviceTypes = [];
    _businessName = null;
    _qualifications = null;
    _hasDBS = false;
    _experience = null;
    _hourlyRate = null;
    _serviceAreas = [];
    _log('All onboarding data cleared');
    await BrowserStorage.remove(_storageKey);
  }
  
  /// Initialize and load data from persistent storage
  Future<void> initialize() async {
    if (_initializationFuture != null) {
      return _initializationFuture;
    }
    
    _initializationFuture = _loadFromStorage();
    return _initializationFuture;
  }
  
  /// Load data from persistent storage
  Future<void> _loadFromStorage() async {
    if (_isInitialized) return;
    
    try {
      final dataJson = await BrowserStorage.getString(_storageKey);
      
      if (dataJson != null) {
        final Map<String, dynamic> data = json.decode(dataJson);
        
        _name = data['name'] as String?;
        _parentType = data['parent_type'] as String?;
        _stagesOfLife = List<String>.from(data['stages_of_life'] ?? []);
        _postcode = data['postcode'] as String?;
        _dueDate = data['due_date'] as String?;
        _children = List<Map<String, String>>.from(
          (data['children'] as List? ?? []).map((e) => Map<String, String>.from(e))
        );
        _phoneNumber = data['phone_number'] as String?;
        _countryCode = data['country_code'] as String?;
        _password = data['password'] as String?;
        _isPhoneVerified = data['is_phone_verified'] as bool? ?? false;
        _profilePhotoPath = data['profile_photo_path'] as String?;
        _bio = data['bio'] as String?;
        _profilePhotoObjectUrl = data['profile_photo_object_url'] as String?;
        _previousPostcode = data['previous_postcode'] as String?;
        _previousBorough = data['previous_borough'] as String?;
        _assignedGroupCount = data['assigned_group_count'] as int? ?? 0;
        _serviceTypes = List<String>.from(data['service_types'] ?? []);
        _businessName = data['business_name'] as String?;
        _qualifications = data['qualifications'] as String?;
        _hasDBS = data['has_dbs'] as bool? ?? false;
        _experience = data['experience'] as String?;
        _hourlyRate = data['hourly_rate'] as String?;
        _serviceAreas = List<String>.from(data['service_areas'] ?? []);
        
        // ignore: avoid_print
        print('✅ OnboardingData loaded from storage');
        // ignore: avoid_print
        print('   Name: $_name');
        // ignore: avoid_print
        print('   Postcode: $_postcode');
        // ignore: avoid_print
        print('   Stages: $_stagesOfLife');
        // ignore: avoid_print
        print('   Phone: $fullPhoneNumber');
      }
      
      _isInitialized = true;
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error loading onboarding data: $e');
    }
  }
  
  /// Save data to persistent storage
  Future<void> _saveToStorage() async {
    try {
      final data = {
        'name': _name,
        'parent_type': _parentType,
        'stages_of_life': _stagesOfLife,
        'postcode': _postcode,
        'due_date': _dueDate,
        'children': _children,
        'phone_number': _phoneNumber,
        'country_code': _countryCode,
        'password': _password,
        'is_phone_verified': _isPhoneVerified,
        'profile_photo_path': _profilePhotoPath,
        'bio': _bio,
        'profile_photo_object_url': _profilePhotoObjectUrl,
        'previous_postcode': _previousPostcode,
        'previous_borough': _previousBorough,
        'assigned_group_count': _assignedGroupCount,
        'service_types': _serviceTypes,
        'business_name': _businessName,
        'qualifications': _qualifications,
        'has_dbs': _hasDBS,
        'experience': _experience,
        'hourly_rate': _hourlyRate,
        'service_areas': _serviceAreas,
      };
      
      await BrowserStorage.setString(_storageKey, json.encode(data));
      _log('Data saved to storage');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error saving onboarding data: $e');
    }
  }

  // Debug logging
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('📝 OnboardingData: $message');
    }
  }

  // Print summary
  void printSummary() {
    if (kDebugMode) {
      debugPrint('=== Onboarding Data Summary ===');
      debugPrint('Name: $_name');
      debugPrint('Parent Type: $_parentType');
      debugPrint('Stages: $_stagesOfLife');
      debugPrint('Postcode: $_postcode');
      debugPrint('Phone: $fullPhoneNumber');
      debugPrint('Phone Verified: $_isPhoneVerified');
      debugPrint('Completion: ${getCompletionPercentage().toStringAsFixed(1)}%');
      debugPrint('==============================');
    }
  }
}
