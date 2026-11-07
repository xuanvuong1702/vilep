import 'package:dio/dio.dart';

const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:5080');

class ApiException implements Exception {
  final String code;
  final String message;
  final int status;

  ApiException(this.code, this.message, this.status);

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final Dio _dio;
  String? token;

  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? kApiBase,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? kApiBase,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          contentType: 'application/json',
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ));

  Map<String, String> _headers({String? idempotencyKey, Map<String, String>? extra}) {
    final headers = <String, String>{};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  dynamic _unwrap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (data['ok'] == true) return data['data'];
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        throw ApiException(
          error['code']?.toString() ?? 'error',
          error['message']?.toString() ?? 'Có lỗi xảy ra',
          response.statusCode ?? 400,
        );
      }
    }
    if ((response.statusCode ?? 500) >= 400) {
      throw ApiException('http_${response.statusCode}', 'Có lỗi xảy ra (${response.statusCode})', response.statusCode ?? 500);
    }
    return data;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get(path, queryParameters: query, options: Options(headers: _headers()));
      return _unwrap(response);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<dynamic> post(String path, {Object? body, String? idempotencyKey, Map<String, String>? headers}) async {
    try {
      final response = await _dio.post(path,
          data: body, options: Options(headers: _headers(idempotencyKey: idempotencyKey, extra: headers)));
      return _unwrap(response);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<dynamic> put(String path, {Object? body}) async {
    try {
      final response = await _dio.put(path, data: body, options: Options(headers: _headers()));
      return _unwrap(response);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final response = await _dio.delete(path, options: Options(headers: _headers()));
      return _unwrap(response);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  ApiException _mapDioError(DioException e) {
    final response = e.response;
    if (response != null && response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        return ApiException(
          error['code']?.toString() ?? 'error',
          error['message']?.toString() ?? 'Có lỗi xảy ra',
          response.statusCode ?? 400,
        );
      }
    }
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return ApiException('network', 'Không kết nối được máy chủ. Kiểm tra API đang chạy?', 0);
    }
    return ApiException('network', e.message ?? 'Lỗi kết nối', response?.statusCode ?? 0);
  }
}
