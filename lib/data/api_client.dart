import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Windows desktop client for the BatiPro PostgreSQL API.
/// Credentials and bearer tokens are kept in the Windows secure credential store.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _urlKey = 'batipro_api_base_url';
  static const String _tokenKey = 'batipro_api_access_token';

  String? _baseUrl;
  String? _token;

  String? get baseUrl => _baseUrl;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> initialize() async {
    _baseUrl = await _secure.read(key: _urlKey);
    _token = await _secure.read(key: _tokenKey);
  }

  String _normalizeBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('أدخل رابط API صحيحاً يبدأ بـ https:// أو http://');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> setServerUrl(String value) async {
    final normalized = _normalizeBaseUrl(value);
    _baseUrl = normalized;
    await _secure.write(key: _urlKey, value: normalized);
    _token = null;
    await _secure.delete(key: _tokenKey);
  }

  Uri _uri(String path) {
    final base = _baseUrl;
    if (base == null || base.isEmpty) {
      throw StateError('أدخل عنوان خادم BatiPro أولاً.');
    }
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (isAuthenticated) 'Authorization': 'Bearer $_token',
      };

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw ApiException(
        response.statusCode,
        detail?.toString() ?? 'فشل الاتصال بالخادم (' + response.statusCode.toString() + ')',
      );
    }
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{'data': decoded};
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          _uri('/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    final data = _decode(response);
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const FormatException('الخادم لم يرجع رمز الدخول.');
    }
    _token = token;
    await _secure.write(key: _tokenKey, value: token);
    return data;
  }

  Future<Map<String, dynamic>> me() async {
    final response = await http
        .get(_uri('/me'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> products() async {
    final response = await http
        .get(_uri('/products'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    final data = _decode(response)['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    throw const FormatException('صيغة قائمة المنتجات غير صحيحة.');
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> product) async {
    final response = await http
        .post(_uri('/products'), headers: _headers, body: jsonEncode(product))
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> warehouses() async {
    final response = await http
        .get(_uri('/warehouses'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    final data = _decode(response)['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    throw const FormatException('صيغة قائمة المستودعات غير صحيحة.');
  }

  Future<List<Map<String, dynamic>>> stock() async {
    final response = await http
        .get(_uri('/stock'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    final data = _decode(response)['data'];
    if (data is List) {
      return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    throw const FormatException('صيغة المخزون غير صحيحة.');
  }

  Future<Map<String, dynamic>> adjustStock({
    required String productId,
    required String warehouseId,
    required num quantityDelta,
    required String unit,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response = await http
        .post(
          _uri('/stock/adjustments'),
          headers: _headers,
          body: jsonEncode({
            'product_id': productId,
            'warehouse_id': warehouseId,
            'quantity_delta': quantityDelta,
            'unit': unit,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response);
  }

  Future<void> logout() async {
    _token = null;
    await _secure.delete(key: _tokenKey);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}
