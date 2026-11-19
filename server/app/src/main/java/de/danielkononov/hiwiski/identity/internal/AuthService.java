package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.DeviceRevoked;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.UUID;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;

/** Log in, log out, change password. */
@Service
class AuthService {

    private final MemberService members;
    private final DeviceRepository devices;
    private final Secrets secrets;
    private final LoginThrottle throttle;
    private final ApplicationEventPublisher events;

    AuthService(
            MemberService members,
            DeviceRepository devices,
            Secrets secrets,
            LoginThrottle throttle,
            ApplicationEventPublisher events) {
        this.members = members;
        this.devices = devices;
        this.secrets = secrets;
        this.throttle = throttle;
        this.events = events;
    }

    /** The token and the session the app continues with. */
    record SignedIn(String token, UUID deviceId, MemberRow member) {}

    /**
     * How a device introduces itself at sign-in.
     *
     * @param installationId the app installation; {@code null} from an older app
     */
    record NewDevice(String name, String platform, boolean staySignedIn, UUID installationId) {}

    /**
     * Not one transaction: the password check takes a while on purpose, and a
     * connection held through it for every attempt let a handful of parallel logins
     * starve the pool. The device is registered in a single insert.
     */
    SignedIn login(String username, String password, NewDevice device, String client) {
        // Counted before the password is checked, so parallel attempts are counted too.
        // Past the username's ceiling, only a known installation gets through (asked
        // only then): the member's own phone is never kept out by a stranger.
        throttle.admit(username, client, () -> knownInstallation(username, device.installationId()));

        // The same answer for "user does not exist", "wrong password" and "disabled":
        // the difference would reveal which usernames exist.
        MemberRow member = members.rowByUsername(username == null ? "" : username).orElse(null);
        // The password is checked in every case, so the answer takes as long for a
        // username that does not exist or is disabled as for a wrong password.
        boolean matches = member == null ? spend(password) : members.passwordMatches(member, password);
        if (member == null || member.disabled() || !matches) {
            throw new HiwiskiException(HttpStatus.UNAUTHORIZED, "auth.invalid_credentials", java.util.Map.of());
        }
        throttle.succeeded(username, client);
        return registerDevice(member, device);
    }

    private boolean knownInstallation(String username, UUID installationId) {
        if (installationId == null || username == null) {
            return false;
        }
        return members.rowByUsername(username)
                .map(member -> devices.installationKnown(installationId, member.id()))
                .orElse(false);
    }

    private boolean spend(String password) {
        members.spendPasswordCheck(password);
        return false;
    }

    /**
     * Registers the device -- and retires what the same installation registered before
     * for this member:
     * signing in again on the same phone or browser used to add a row each time, and
     * the device list filled with entries whose token nobody held any more.
     */
    @Transactional
    SignedIn registerDevice(MemberRow member, NewDevice device) {
        if (device.installationId() != null) {
            devices.retireInstallation(device.installationId(), member.id())
                    .forEach(id -> events.publishEvent(new DeviceRevoked(id)));
        }
        String token = secrets.newToken();
        UUID deviceId = UUID.randomUUID();
        String name = device.name();
        devices.insert(
                deviceId,
                member.id(),
                name == null || name.isBlank() ? "Unnamed device" : MemberService.shortened(name.trim()),
                device.platform() == null ? "UNKNOWN" : device.platform(),
                secrets.hashToken(token),
                device.staySignedIn(),
                device.installationId());
        return new SignedIn(token, deviceId, member);
    }

    /**
     * Ends the devices that ended on their own -- a session idle for 12 hours, any
     * device idle for 180 days -- hourly. The token filter
     * refuses them already; this takes them out of the device list.
     */
    @Scheduled(cron = "0 23 * * * *")
    @Transactional
    void revokeExpired() {
        devices.revokeExpired().forEach(id -> events.publishEvent(new DeviceRevoked(id)));
    }

    @Transactional
    void logout(UUID memberId, UUID deviceId) {
        if (devices.revoke(deviceId, memberId) > 0) {
            events.publishEvent(new DeviceRevoked(deviceId));
        }
    }

    @Transactional
    void revokeDevice(UUID memberId, UUID deviceId) {
        if (devices.revoke(deviceId, memberId) == 0) {
            // Here too 404 instead of 403: someone else's device should not give away
            // that it exists.
            throw HiwiskiException.notFound("identity.device_not_found", "deviceId", deviceId);
        }
        events.publishEvent(new DeviceRevoked(deviceId));
    }

    /**
     * Change your own password -- and sign out this member's other devices.
     *
     * <p>A new password is how a member locks out whoever learned the old one; a device
     * signed in with it must not keep working. They used to stay signed in, on the
     * grounds that a change mostly follows a reset by the administrator -- but the reset
     * signs out every device already, so after one there is nothing else to sign out.
     */
    @Transactional
    void changePassword(
            UUID memberId, UUID currentDevice, String currentPassword, String newPassword, String client) {
        MemberRow member =
                members.row(memberId)
                        .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found", "memberId", memberId));
        // Delayed like a sign-in: a stolen token could otherwise guess the password
        // itself, without limit -- and the password outlives revoking the token. The
        // device is signed in, so the username's ceiling does not keep it out: a member
        // whose account is being guessed at must still be able to change the password.
        throttle.admit(member.username(), client, () -> true);
        if (!members.passwordMatches(member, currentPassword)) {
            throw HiwiskiException.invalid("auth.current_password_wrong");
        }
        throttle.succeeded(member.username(), client);
        // The change after a reset is what takes the password out of the
        // administrator's hands; "changed" to the temporary one itself, the prompt went
        // away and the administrator still knew it.
        if (newPassword != null && newPassword.equals(currentPassword)) {
            throw HiwiskiException.invalid("auth.new_password_same");
        }
        members.setPassword(memberId, newPassword, false);
        signOut(memberId, currentDevice);
    }

    /** Revokes the member's devices but {@code keep}, telling each one it is out. */
    private void signOut(UUID memberId, UUID keep) {
        devices.revokeAllOf(memberId, keep).forEach(id -> events.publishEvent(new DeviceRevoked(id)));
    }

    /**
     * The administrator disables a member: no sign-in, no session (the token filter
     * checks {@code disabled_at} on every call), and every device signed out at once,
     * each told so. Their things and shares stay.
     *
     * <p>Before this the administrator had no lever at all against a stolen phone or a
     * member who left on bad terms: a password reset held only until the member chose a
     * new one.
     */
    @Transactional
    void disableMember(UUID memberId) {
        requireNotAdmin(memberId);
        members.setDisabled(memberId, true);
        signOut(memberId, null);
    }

    /** The member may sign in again; the devices signed out stay signed out. */
    @Transactional
    void enableMember(UUID memberId) {
        members.row(memberId)
                .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found", "memberId", memberId));
        members.setDisabled(memberId, false);
    }

    /** The administrator signs out every device of a member; they can sign in again. */
    @Transactional
    void signOutMember(UUID memberId) {
        requireNotAdmin(memberId);
        signOut(memberId, null);
    }

    /**
     * The administrator is not disabled or signed out from the family screen: their
     * own devices are in their own device list, and a disabled administrator would lock
     * the family out of its server.
     */
    private void requireNotAdmin(UUID memberId) {
        MemberRow member =
                members.row(memberId)
                        .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found", "memberId", memberId));
        if (member.isAdmin()) {
            throw HiwiskiException.invalid("identity.member_is_admin");
        }
    }

    /**
     * The administrator sets a temporary password.
     *
     * <p>It is returned once and cannot be retrieved again afterwards. For the
     * administrator themselves there is no way through the app -- that is what the
     * command in the container is for.
     *
     * <p>Every device of the member is signed out. Restricted to the password screen
     * only, the old tokens became fully valid again once the member chose a new
     * password -- a device someone else signed into with a leaked password included.
     */
    @Transactional
    String resetPassword(UUID memberId) {
        MemberRow member =
                members.row(memberId)
                        .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found", "memberId", memberId));
        if (member.isAdmin()) {
            throw HiwiskiException.invalid("identity.admin_password_needs_container_command");
        }
        String temporary = secrets.newTemporaryPassword();
        members.setPassword(memberId, temporary, true);
        signOut(memberId, null);
        return temporary;
    }
}
