import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'hiwiski_failure.dart';
import 'generated/export.dart';
import 'backup_file_client.dart';
import 'image_client.dart';

/// Access to the server.
///
/// This is where the device token is attached to every request, and where every Dio
/// exception is translated into a [HiwiskiFailure]. The calls themselves come from the
/// spec; generated code is never tinkered with.
class HiwiskiApi {
  static const _authorization = 'Authorization';
  static const _bearer = 'Bearer';

  HiwiskiApi({required this.tokens, String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? '',
          // Kept short: an unreachable home server is the normal case on the go,
          // and the app should not stand still for half a minute before it says
          // "offline".
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          // The caller evaluates status codes; Dio should not throw on its own
          // before the error body has been read.
          validateStatus: (status) => status != null && status < 400,
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) =>
            unawaited(_authorize(options, handler)),
      ),
    );
  }

  final Dio _dio;
  final TokenStore tokens;

  /// Calls that take as long as the archive is large — without a timeout.
  static const _backupPaths = [
    '/api/v1/admin/backups',
    '/api/v1/setup/uploads',
  ];

  Future<void> _authorize(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // **No server, no request.** Without an address — the app used without a server,
    // the demo — a call went to a path relative to wherever the app came
    // from: on the web, the page's own host answered with its `index.html`. A call
    // that slips through is unreachable instead, which every caller already handles
    // as offline.
    if (options.baseUrl.isEmpty) {
      handler.reject(
        DioException(requestOptions: options, type: .connectionError),
      );
      return;
    }
    // A backup writes, a restore migrates and swaps, an archive goes up or down: on a
    // small server with years of photos that takes minutes, not the twenty seconds
    // a call is given.
    if (_backupPaths.any(options.path.startsWith)) {
      options
        ..receiveTimeout = Duration.zero
        ..sendTimeout = Duration.zero;
    }
    try {
      final token = await tokens.read();
      if (token != null && token.isNotEmpty) {
        options.headers[_authorization] = '$_bearer $token';
      }
      handler.next(options);
    } catch (error, stackTrace) {
      // An unreadable token fails the request, not the app.
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Dio get dio => _dio;

  String get baseUrl => _dio.options.baseUrl;

  set baseUrl(String value) => _dio.options.baseUrl = value;

  PlatformClient get platform => .new(_dio);

  SetupClient get setup => .new(_dio);

  AuthClient get auth => .new(_dio);

  /// The auth calls in the name of [token] instead of the stored one — for a
  /// sign-out, which drops the token on the device first and tells the server
  /// afterwards. By then the store is empty, or already holds the token of whoever
  /// signed in next: without the interceptor, that one cannot slip in and be revoked.
  AuthClient authAs(String token) => .new(
    _dio.clone(
      options: _dio.options.copyWith(
        headers: {..._dio.options.headers, _authorization: '$_bearer $token'},
      ),
      interceptors: Interceptors(),
    ),
  );

  DevicesClient get devices => .new(_dio);

  MembersClient get members => .new(_dio);

  GroupsClient get groups => .new(_dio);

  InvitationsClient get invitations => .new(_dio);

  /// Pull and push. Everything that lives on the device goes through this --
  /// there is deliberately no CRUD over REST for synced entities.
  SyncClient get sync => .new(_dio);

  /// The share sheet. The same on every item.
  AccessClient get access => .new(_dio);

  /// Trash -- without it every disappearance is final.
  TrashClient get trash => .new(_dio);

  /// Settings, backups, log -- administrator only.
  AdminClient get admin => .new(_dio);

  /// Archives in and out, streamed — by hand, see [BackupFileClient].
  BackupFileClient get backupFiles => .new(_dio);

  /// Restoring an archive on a fresh server, from the setup wizard.
  SetupRestoreClient get setupRestore => .new(_dio);

  /// Only the trigger for a subscription sync. Calendars and events themselves go
  /// through sync — a second write path would have to implement sharing and conflict
  /// logic twice.
  CalendarClient get calendar => .new(_dio);

  /// History, links and recipe import. The pages themselves go through sync —
  /// revisions never change and are rarely needed.
  WikiClient get wiki => .new(_dio);

  /// The product catalog — the only domain entity without an owner and without sharing.
  CatalogClient get catalog => .new(_dio);

  /// The wall tablet board under its own address — **without sign-in**.
  DashboardClient get dashboard => .new(_dio);

  /// Search and history. On the server the share check sits **in the same query** as
  /// the hits.
  SearchClient get search => .new(_dio);

  /// Images on pages and recipes — by hand, see [ImageClient].
  ImageClient get images => .new(_dio);

  /// Runs a call and translates every error into a [HiwiskiFailure].
  ///
  /// That way no call site has a `catch (DioException)` — and none forgets it.
  static Future<T> run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (error, stack) {
      Error.throwWithStackTrace(HiwiskiFailure.from(error), stack);
    }
  }
}
