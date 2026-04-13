import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import 'api_client.dart';

class AuthBootstrapService {
  AuthBootstrapService(this._apiClient);

  final ApiClient _apiClient;

  Future<void> loginDefaultAdmin(AppConfig config) async {
    const maxAttempts = 4;
    DioException? lastDioError;
    Object? lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _apiClient.dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {
            'email': config.adminEmail,
            'password': config.adminPassword,
          },
        );

        // 404 means the backend has no auth endpoint (e.g. Docker demo API).
        // Proceed without a bearer token — all requests will go unauthenticated.
        if (response.statusCode == 404) return;

        if (response.statusCode == 200) {
          final token = response.data?['access_token'] as String?;
          if (token != null && token.isNotEmpty) {
            _apiClient.setBearerToken(token);
          }
          return;
        }

        throw DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: response,
          message: 'Login failed with status ${response.statusCode}',
        );
      } on DioException catch (error) {
        lastDioError = error;
        final transient = _isTransient(error);
        if (!transient || attempt == maxAttempts) {
          rethrow;
        }
      } catch (error) {
        lastError = error;
        if (attempt == maxAttempts) {
          rethrow;
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }

    if (lastDioError != null) {
      throw lastDioError!;
    }
    if (lastError != null) {
      throw lastError!;
    }
  }

  bool _isTransient(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.unknown;
  }
}
