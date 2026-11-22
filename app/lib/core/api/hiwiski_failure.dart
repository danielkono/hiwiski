import 'dart:convert';

import 'package:dio/dio.dart';

import '../common/sync_limits.dart';

/// The error codes the client reacts to; the full list is in the
/// OpenAPI description.
abstract final class FailureCodes {
  static const networkUnreachable = 'network.unreachable';

  static const authRequired = 'auth.required';
  static const authInvalidCredentials = 'auth.invalid_credentials';
  static const authCurrentPasswordWrong = 'auth.current_password_wrong';
  static const authNewPasswordSame = 'auth.new_password_same';
  static const authTooManyAttempts = 'auth.too_many_attempts';

  static const accessDenied = 'access.denied';
  static const accessNotShareable = 'access.not_shareable';
  static const accessCheckNotApplicable = 'access.check_not_applicable';
  static const calendarReadOnly = 'calendar.read_only';
  static const calendarFeedTokenInvalid = 'calendar.feed_token_invalid';
  static const calendarFeedNotFound = 'calendar.feed_not_found';
  static const syncValueTooLarge = SyncLimits.valueTooLarge;
  static const syncEntityDeleted = 'sync.entity_deleted';

  static const archiveReadOnly = 'archive.read_only';

  static const todoKindLocked = 'todo.kind_locked';
  static const todoKanbanColumnsInvalid = 'todo.kanban_columns_invalid';
  static const todoKanbanNoRepeat = 'todo.kanban_no_repeat';

  static const catalogAisleNameTaken = 'catalog.aisle_name_taken';
  static const catalogAisleBuiltin = 'catalog.aisle_builtin';
  static const catalogAisleNotFound = 'catalog.aisle_not_found';
  static const catalogAisleNameRequired = 'catalog.aisle_name_required';
  static const catalogProductNameRequired = 'catalog.product_name_required';

  static const identityUsernameTaken = 'identity.username_taken';
  static const identityIdTaken = 'identity.id_taken';
  static const identityUsernameInvalid = 'identity.username_invalid';
  static const identityPasswordTooShort = 'identity.password_too_short';
  static const identityAdminRequired = 'identity.admin_required';
  static const identityMemberIsAdmin = 'identity.member_is_admin';
  static const identityTextTooLong = 'identity.text_too_long';
  static const identityInvitationNotFound = 'identity.invitation_not_found';
  static const identityDeviceNotFound = 'identity.device_not_found';

  /// The wall tablet's address opens no board: replaced, or the board is gone.
  static const dashboardBoardNotFound = 'dashboard.board_not_found';
  static const identityAvatarInvalid = 'identity.avatar_invalid';
  static const identityGroupDefault = 'identity.group_default';

  static const setupAlreadyCompleted = 'setup.already_completed';
  static const setupTimezoneInvalid = 'setup.timezone_invalid';
  static const setupCodeInvalid = 'setup.code_invalid';
  static const setupBackupPasswordSame = 'setup.backup_password_same';

  /// Every change while a backup is restored (`503`, with `Retry-After`).
  static const instanceRestoring = 'instance.restoring';

  static const backupPasswordWrong = 'admin.backup_password_wrong';
  static const backupTooNew = 'admin.backup_too_new';
  static const backupOtherFamily = 'admin.backup_other_family';
  static const paramFamilyName = 'familyName';
  static const backupInvalid = 'admin.backup_invalid';
  static const backupFailed = 'admin.backup_failed';
  static const backupPasswordMissing = 'admin.backup_password_missing';
  static const backupPasswordTooShort = 'admin.backup_password_too_short';
  static const backupNotFound = 'admin.backup_not_found';
  static const backupUploadNotFound = 'admin.backup_upload_not_found';

  /// The parameters of the backup errors.
  static const paramServerVersion = 'serverVersion';
  static const paramReason = 'reason';

  static const mediaNotAnImage = 'media.not_an_image';
  static const mediaTooLarge = 'media.too_large';
  static const mediaOwnerReadOnly = 'media.owner_read_only';
  static const mediaQuotaExceeded = 'media.quota_exceeded';
  static const mediaBusy = 'media.busy';
  static const mediaIdTaken = 'media.id_taken';
  static const mediaImageNotFound = 'media.image_not_found';

  static const netUrlInvalid = 'net.url_invalid';
  static const netUrlSchemeNotAllowed = 'net.url_scheme_not_allowed';
  static const netHostUnknown = 'net.host_unknown';
  static const netAddressNotAllowed = 'net.address_not_allowed';

  static const calendarIcsUnreadable = 'calendar.ics_unreadable';
  static const calendarImportIntoSubscription =
      'calendar.import_into_subscription';
  static const calendarImportSourceMissing = 'calendar.import_source_missing';
  static const calendarImportTargetExists = 'calendar.import_target_exists';
  static const calendarSubscriptionHttpError =
      'calendar.subscription_http_error';
  static const calendarSubscriptionUnreachable =
      'calendar.subscription_unreachable';
  static const calendarSubscriptionTooLarge = 'calendar.subscription_too_large';
  static const calendarSubscriptionTooManyRedirects =
      'calendar.subscription_too_many_redirects';
  static const calendarSubscriptionFailed = 'calendar.subscription_failed';
  static const calendarSubscriptionReadOnly = 'calendar.subscription_read_only';

  static const serverError = 'server.error';

  /// The request as a whole: unreadable or too many mutations (`400`), too large a
  /// body (`413`).
  static const requestInvalid = 'request.invalid';
  static const requestTooLarge = 'request.too_large';

  static const adminKeyPrefixTaken = 'admin.key_prefix_taken';

  static const syncConstraintViolated = 'sync.constraint_violated';

  /// Set by the app, not the server: a change parked for a board that never came.
  static const syncBoardGone = 'sync.board_gone';
  static const syncContainerNotFound = 'sync.container_not_found';

  static const trashContainerGone = 'trash.container_gone';
  static const trashItemNotFound = 'trash.item_not_found';

  /// The prefix of every access error: whatever the reason, the item is gone for
  /// this reader.
  static const accessPrefix = 'access.';
}

/// An error as it comes from the server: **code plus parameters, never a finished
/// sentence**.
///
/// Translation happens in the client via ARB. An unknown code is shown as the code —
/// ugly and honest, and better than an empty dialog.
class HiwiskiFailure implements Exception {
  const HiwiskiFailure({
    required this.code,
    this.params = const {},
    this.correlationId,
    this.status,
  });

  /// The server was unreachable. On the go that is not an error but everyday life —
  /// the UI says "offline", not "broken".
  const HiwiskiFailure.network()
    : code = FailureCodes.networkUnreachable,
      params = const {},
      correlationId = null,
      status = null;

  /// What a proxy answers when the server behind it does not.
  static const _gatewayStatuses = {502, 503, 504};

  // The fields of the error body.
  static const _codeField = 'code';
  static const _paramsField = 'params';
  static const _correlationIdField = 'correlationId';

  final String code;
  final Map<String, String> params;
  final String? correlationId;
  final int? status;

  bool get isNetwork => code == FailureCodes.networkUnreachable;

  bool get isUnauthorized => status == 401;

  /// Worth trying again later: the server failed, was too busy or timed out. A 4xx
  /// other than these is the request's own and will not change on a retry.
  bool get isTransient {
    final code = status;
    return code != null && (code >= 500 || code == 429 || code == 408);
  }

  /// Turns a Dio exception into the error the UI shows.
  factory HiwiskiFailure.from(Object error) {
    if (error is HiwiskiFailure) return error;
    if (error is! DioException) {
      return const HiwiskiFailure(code: FailureCodes.serverError);
    }
    switch (error.type) {
      case .connectionError:
      case .connectionTimeout:
      case .sendTimeout:
      case .receiveTimeout:
        return const HiwiskiFailure.network();
      default:
        break;
    }
    final response = error.response;
    final data = _bodyOf(response?.data);
    final body = data is Map ? data : const <Object?, Object?>{};
    final code = switch (body) {
      {_codeField: final String code} => code,
      _ => null,
    };
    final hiwiskiBody = code != null;
    // A reverse proxy in front of a server that is down answers 502, 503 or 504 with
    // a page of its own. That is the server being unreachable, not an error of it:
    // as "server error" it skipped every offline path — the cached share sheet, the
    // queued shares, the sync's "offline".
    if (!hiwiskiBody && _gatewayStatuses.contains(response?.statusCode)) {
      return const HiwiskiFailure.network();
    }
    if (code != null) {
      return HiwiskiFailure(
        code: code,
        params: {
          for (final entry in (body[_paramsField] as Map? ?? const {}).entries)
            '${entry.key}': '${entry.value}',
        },
        correlationId: body[_correlationIdField] as String?,
        status: response?.statusCode,
      );
    }
    return HiwiskiFailure(
      code: FailureCodes.serverError,
      status: response?.statusCode,
    );
  }

  /// An error's body as JSON — read from bytes too: an endpoint that answers with
  /// bytes (an image, a backup) gets its error as bytes as well. Unread, its code was
  /// lost: a picture not uploaded yet looked like a server error, and was never asked
  /// for again.
  static Object? _bodyOf(Object? data) {
    if (data is! List<int>) return data;
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'HiwiskiFailure($code, $params)';
}
