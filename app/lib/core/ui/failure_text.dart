import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';
import '../api/hiwiski_failure.dart';

/// Translates an error code into a sentence.
///
/// Two callers: the error display of a failed call — and the note on an ICS
/// subscription, which is stored as a code **on the item** and still shows days later.
/// That is why [failureTextForCode] takes a bare code.
///
/// An **unknown code is shown as the code**. That is ugly and honest: an
/// older app must not swallow a new error from the server, and a generic "Error"
/// would be worthless to whoever is helping.
String failureText(BuildContext context, HiwiskiFailure failure) =>
    failureTextForCode(
      context,
      failure.code,
      correlationId: failure.correlationId,
      params: failure.params,
    );

/// Like [failureText], but for a code with no call behind it.
String failureTextForCode(
  BuildContext context,
  String code, {
  String? correlationId,
  Map<String, String> params = const {},
}) {
  final l = L.of(context);
  return switch (code) {
    FailureCodes.networkUnreachable => l.errorNetwork,
    FailureCodes.authRequired => l.errorAuthRequired,
    FailureCodes.authInvalidCredentials => l.errorAuthInvalidCredentials,
    FailureCodes.authCurrentPasswordWrong => l.errorAuthCurrentPasswordWrong,
    FailureCodes.authNewPasswordSame => l.errorAuthNewPasswordSame,
    FailureCodes.authTooManyAttempts => l.errorAuthTooManyAttempts,
    FailureCodes.accessDenied => l.errorAccessDenied,
    FailureCodes.calendarReadOnly => l.errorCalendarReadOnly,
    FailureCodes.calendarFeedTokenInvalid => l.errorCalendarFeedTokenInvalid,
    FailureCodes.syncValueTooLarge => l.errorSyncValueTooLarge,
    FailureCodes.requestInvalid => l.errorRequestInvalid,
    FailureCodes.requestTooLarge => l.errorRequestTooLarge,
    FailureCodes.identityMemberIsAdmin => l.errorIdentityMemberIsAdmin,
    FailureCodes.identityTextTooLong => l.errorIdentityTextTooLong,
    FailureCodes.accessNotShareable => l.errorAccessNotShareable,
    FailureCodes.calendarFeedNotFound => l.errorCalendarFeedNotFound,
    FailureCodes.syncEntityDeleted => l.errorSyncEntityDeleted,
    FailureCodes.syncContainerNotFound => l.errorSyncContainerNotFound,
    FailureCodes.adminKeyPrefixTaken => l.errorAdminKeyPrefixTaken,
    FailureCodes.syncBoardGone => l.errorSyncBoardGone,
    FailureCodes.wikiNotAPinboard => l.errorWikiNotAPinboard,
    FailureCodes.wikiPinboardElementGone => l.errorWikiPinboardElementGone,
    FailureCodes.dashboardBoardNotFound => l.errorDashboardBoardNotFound,
    // An archived item is read-only — also for a change made offline before someone
    // archived it.
    FailureCodes.archiveReadOnly => l.errorArchiveReadOnly,
    // A board's rules hold on the server too — a device that was
    // offline during a conversion learns it here.
    FailureCodes.todoKindLocked => l.errorTodoKindLocked,
    FailureCodes.todoKanbanColumnsInvalid => l.errorKanbanColumnsInvalid,
    FailureCodes.todoKanbanNoRepeat => l.errorKanbanNoRepeat,
    FailureCodes.accessCheckNotApplicable => l.errorAccessCheckNotApplicable,
    FailureCodes.catalogAisleNameTaken => l.errorCatalogAisleNameTaken,
    FailureCodes.catalogAisleBuiltin => l.errorCatalogAisleBuiltin,
    FailureCodes.catalogAisleNotFound => l.errorCatalogAisleNotFound,
    FailureCodes.identityUsernameTaken => l.errorIdentityUsernameTaken,
    FailureCodes.identityIdTaken => l.errorIdentityIdTaken,
    FailureCodes.identityUsernameInvalid => l.errorIdentityUsernameInvalid,
    FailureCodes.identityPasswordTooShort => l.errorIdentityPasswordTooShort,
    FailureCodes.identityAdminRequired => l.errorIdentityAdminRequired,
    FailureCodes.identityInvitationNotFound =>
      l.errorIdentityInvitationNotFound,
    FailureCodes.identityDeviceNotFound => l.errorIdentityDeviceNotFound,
    FailureCodes.identityGroupDefault => l.errorIdentityGroupDefault,
    FailureCodes.setupAlreadyCompleted => l.errorSetupAlreadyCompleted,
    FailureCodes.setupTimezoneInvalid => l.errorSetupTimezoneInvalid,
    FailureCodes.setupCodeInvalid => l.errorSetupCodeInvalid,
    FailureCodes.setupBackupPasswordSame => l.errorSetupBackupPasswordSame,
    FailureCodes.backupPasswordWrong => l.errorBackupPasswordWrong,
    FailureCodes.instanceRestoring => l.errorInstanceRestoring,
    FailureCodes.backupTooNew => l.errorBackupTooNew(
      params[FailureCodes.paramServerVersion] ?? '?',
    ),
    FailureCodes.backupInvalid => l.errorBackupInvalid,
    FailureCodes.backupOtherFamily => l.errorBackupOtherFamily(
      params[FailureCodes.paramFamilyName] ?? '?',
    ),
    FailureCodes.backupFailed => l.errorBackupFailed(
      backupFailureText(l, params[FailureCodes.paramReason]),
    ),
    FailureCodes.backupPasswordMissing => l.errorBackupPasswordMissing,
    FailureCodes.backupPasswordTooShort => l.errorBackupPasswordTooShort,
    FailureCodes.backupNotFound => l.errorBackupNotFound,
    FailureCodes.backupUploadNotFound => l.errorBackupUploadNotFound,
    FailureCodes.mediaNotAnImage => l.errorMediaNotAnImage,
    FailureCodes.mediaTooLarge => l.errorMediaTooLarge,
    FailureCodes.mediaOwnerReadOnly => l.errorMediaOwnerReadOnly,
    FailureCodes.mediaQuotaExceeded => l.errorMediaQuotaExceeded,
    FailureCodes.mediaBusy => l.errorMediaBusy,
    FailureCodes.netUrlInvalid => l.errorNetUrlInvalid,
    FailureCodes.netUrlSchemeNotAllowed => l.errorNetUrlSchemeNotAllowed,
    FailureCodes.netHostUnknown => l.errorNetHostUnknown,
    // The SSRF protection: recipe import and ICS subscription check the resolved IP
    // against private ranges, loopback, link-local and metadata addresses — before and
    // after every redirect.
    FailureCodes.netAddressNotAllowed => l.errorNetAddressNotAllowed,
    FailureCodes.calendarIcsUnreadable => l.errorCalendarIcsUnreadable,
    FailureCodes.calendarImportIntoSubscription =>
      l.errorCalendarImportIntoSubscription,
    FailureCodes.calendarImportSourceMissing =>
      l.errorCalendarImportSourceMissing,
    FailureCodes.identityAvatarInvalid => l.errorIdentityAvatarInvalid,
    FailureCodes.calendarImportTargetExists =>
      l.errorCalendarImportTargetExists,
    FailureCodes.calendarSubscriptionHttpError =>
      l.errorCalendarSubscriptionHttpError,
    FailureCodes.calendarSubscriptionUnreachable =>
      l.errorCalendarSubscriptionUnreachable,
    FailureCodes.calendarSubscriptionTooLarge =>
      l.errorCalendarSubscriptionTooLarge,
    FailureCodes.calendarSubscriptionTooManyRedirects =>
      l.errorCalendarSubscriptionTooManyRedirects,
    FailureCodes.calendarSubscriptionFailed =>
      l.errorCalendarSubscriptionFailed,
    FailureCodes.calendarSubscriptionReadOnly =>
      l.errorCalendarSubscriptionReadOnly,
    FailureCodes.serverError => l.errorServerGeneric(correlationId ?? '—'),
    _ => code,
  };
}

/// Why a backup failed, as the server names it (`BackupFailure.reason`).
String backupFailureText(L l, String? reason) => switch (reason) {
  _directoryNotWritable => l.backupFailureDirectory,
  _diskFull => l.backupFailureDiskFull,
  _noBackupPassword => l.backupFailureNoPassword,
  _ => l.backupFailureOther,
};

const _directoryNotWritable = 'DIRECTORY_NOT_WRITABLE';
const _diskFull = 'DISK_FULL';
const _noBackupPassword = 'NO_BACKUP_PASSWORD';
