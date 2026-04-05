import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// RevGlue iframeapi service — connects to your RevEmbed Publisher ID 1202.
/// All affiliate exit-clicks route through RevGlue's tracking so you earn 80 %
/// commission on every purchase.
class RevGlueService {
  static final RevGlueService _instance = RevGlueService._internal();
  factory RevGlueService() => _instance;
  RevGlueService._internal();

  static const String _publisherId = '1202';
  static const String _baseUrl = 'https://www.revglue.com/iframeapi';

  // ── Cached data ──────────────────────────────────────────────────
  List<RevGlueStore>? _cachedStores;
  List<RevGlueCategory>? _cachedCategories;
  DateTime? _storesCacheTime;
  DateTime? _categoriesCacheTime;
  static const _cacheDuration = Duration(minutes: 30);

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheDuration;
  }

  // ── Top stores ───────────────────────────────────────────────────
  Future<List<RevGlueStore>> getTopStores({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_storesCacheTime) && _cachedStores != null) {
      return _cachedStores!;
    }
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/top_stores/$_publisherId'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        _cachedStores = data.map((e) => RevGlueStore.fromJson(e)).toList();
        _storesCacheTime = DateTime.now();
        return _cachedStores!;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RevGlue top_stores error: $e');
    }
    return _cachedStores ?? [];
  }

  // ── Categories ───────────────────────────────────────────────────
  Future<List<RevGlueCategory>> getCategories({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_categoriesCacheTime) && _cachedCategories != null) {
      return _cachedCategories!;
    }
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/coupon_allcategories/$_publisherId'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        _cachedCategories = data.map((e) => RevGlueCategory.fromJson(e)).toList();
        _categoriesCacheTime = DateTime.now();
        return _cachedCategories!;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RevGlue categories error: $e');
    }
    return _cachedCategories ?? [];
  }

  // ── Menu categories (top-level with sub-cats) ────────────────────
  Future<List<RevGlueCategory>> getMenuCategories() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/coupon_menu_categories/$_publisherId'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        return data.map((e) => RevGlueCategory.fromJson(e)).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RevGlue menu_categories error: $e');
    }
    return [];
  }

  // ── Stores filtered by category / subcategory ─────────────────
  Future<List<RevGlueStore>> getCategoryStores(String categoryId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/top_stores/$_publisherId/$categoryId'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        return data.map((e) => RevGlueStore.fromJson(e)).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RevGlue category_stores error: $e');
    }
    return [];
  }

  // ── Store detail (returns list of vouchers for a store) ──────────
  Future<List<RevGlueCoupon>> getStoreVouchers(String storeId, {int page = 1}) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/store_detail/$_publisherId/$storeId/$page'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is List) {
          return decoded.map((e) => RevGlueCoupon.fromJson(e)).toList();
        } else if (decoded is Map<String, dynamic>) {
          // Single coupon returned as map
          return [RevGlueCoupon.fromJson(decoded)];
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RevGlue store_detail error: $e');
    }
    return [];
  }

  // ── Homepage banners ─────────────────────────────────────────────
  Future<List<RevGlueBanner>> getHomeBanners() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/homepage_placement_banners/$_publisherId'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(res.body);
        final banners = <RevGlueBanner>[];
        data.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            banners.add(RevGlueBanner.fromJson(val));
          }
        });
        return banners;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RevGlue banners error: $e');
    }
    return [];
  }

  // ── Build affiliate exit-click URLs ──────────────────────────────
  static String couponExitUrl(String storeId) =>
      'https://www.revglue.com/revembed/coupon_exitclick/$_publisherId/$storeId';

  static String dailyDealExitUrl(String storeId, String dealId) =>
      'https://www.revglue.com/revembed/daily_deal_exitclick/$_publisherId/$storeId/$dealId';
}

// ══════════════════════════════════════════════════════════════════
//  Models
// ══════════════════════════════════════════════════════════════════

class RevGlueStore {
  final String id;
  final String title;
  final String titleUrl;
  final String offerCouponStr;
  final String storeIcon;
  final String storeLargeIcon;

  const RevGlueStore({
    required this.id,
    required this.title,
    required this.titleUrl,
    required this.offerCouponStr,
    required this.storeIcon,
    required this.storeLargeIcon,
  });

  factory RevGlueStore.fromJson(Map<String, dynamic> j) => RevGlueStore(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        titleUrl: j['title_url']?.toString() ?? '',
        offerCouponStr: j['offercoupon_str']?.toString() ?? '',
        storeIcon: j['store_icon']?.toString() ?? '',
        storeLargeIcon: j['store_large_icon']?.toString() ?? '',
      );
}

class RevGlueCategory {
  final String id;
  final String title;
  final String catUrl;
  final String offerCouponStr;
  final String? smallIcon;
  final String? largeIcon;
  final List<RevGlueCategory> subCategories;

  const RevGlueCategory({
    required this.id,
    required this.title,
    required this.catUrl,
    required this.offerCouponStr,
    this.smallIcon,
    this.largeIcon,
    this.subCategories = const [],
  });

  factory RevGlueCategory.fromJson(Map<String, dynamic> j) {
    final subs = (j['sub'] as List? ?? j['sub_cat'] as List? ?? [])
        .map((s) => RevGlueCategory.fromJson(s as Map<String, dynamic>))
        .toList();
    return RevGlueCategory(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      catUrl: j['cat_url']?.toString() ?? '',
      offerCouponStr: j['offercoupon_str']?.toString() ?? '',
      smallIcon: j['small_icon']?.toString(),
      largeIcon: j['large_icon']?.toString(),
      subCategories: subs,
    );
  }
}

class RevGlueCoupon {
  final String id;
  final String storeId;
  final String storeTitle;
  final String titleUrl;
  final String voucherCode;
  final String voucherTitle;
  final String storeIcon;
  final String expiryDate;
  final String offerCoupon; // "Offer" or "Code"
  final String title;

  const RevGlueCoupon({
    required this.id,
    required this.storeId,
    required this.storeTitle,
    required this.titleUrl,
    required this.voucherCode,
    required this.voucherTitle,
    required this.storeIcon,
    required this.expiryDate,
    required this.offerCoupon,
    required this.title,
  });

  bool get hasCode => voucherCode.isNotEmpty;

  factory RevGlueCoupon.fromJson(Map<String, dynamic> j) => RevGlueCoupon(
        id: j['id']?.toString() ?? '',
        storeId: j['store_id']?.toString() ?? '',
        storeTitle: j['store_title']?.toString() ?? '',
        titleUrl: j['title_url']?.toString() ?? '',
        voucherCode: j['voucher_code']?.toString() ?? '',
        voucherTitle: j['voucher_title']?.toString() ?? '',
        storeIcon: j['store_icon']?.toString() ?? '',
        expiryDate: j['expiry_date']?.toString() ?? '',
        offerCoupon: j['offer_coupon']?.toString() ?? 'Offer',
        title: j['title']?.toString() ?? '',
      );
}

class RevGlueBanner {
  final String src;
  final String storeId;
  final String titleUrl;
  final String title;

  const RevGlueBanner({
    required this.src,
    required this.storeId,
    required this.titleUrl,
    required this.title,
  });

  factory RevGlueBanner.fromJson(Map<String, dynamic> j) => RevGlueBanner(
        src: j['src']?.toString() ?? '',
        storeId: j['href']?.toString() ?? '',
        titleUrl: j['title_url']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
      );
}
