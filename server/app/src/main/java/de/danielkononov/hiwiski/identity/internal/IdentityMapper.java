package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.model.ColorToken;
import de.danielkononov.hiwiski.api.model.Device;
import de.danielkononov.hiwiski.api.model.DevicePlatform;
import de.danielkononov.hiwiski.api.model.DeviceRegistration;
import de.danielkononov.hiwiski.api.model.Group;
import de.danielkononov.hiwiski.api.model.Invitation;
import de.danielkononov.hiwiski.api.model.Member;
import de.danielkononov.hiwiski.api.model.Session;
import de.danielkononov.hiwiski.api.model.SignedIn;
import de.danielkononov.hiwiski.api.model.AppearanceMode;
import de.danielkononov.hiwiski.identity.GroupInfo;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * Domain to contract.
 *
 * <p>By hand instead of MapStruct: the mapping is not mechanical in two places --
 * unknown tokens fall back to a default instead of throwing. An enum value this server
 * version does not know must not cost a response.
 */
@Component
class IdentityMapper {

    Member toApi(MemberRow row) {
        Member member =
                new Member(row.id(), row.username(), row.displayName(), row.isAdmin(), colorToken(row.colorToken()));
        member.setGroupIds(row.groupIds());
        member.setDisabled(row.disabled());
        member.setCreatedAt(row.createdAt());
        member.setAvatarImageId(row.avatarImageId());
        return member;
    }

    Session toSession(MemberRow row, UUID deviceId) {
        Session session = new Session(toApi(row), deviceId, row.mustChangePassword());
        session.setAppearance(appearance(row.themeMode()));
        return session;
    }

    SignedIn toSignedIn(AuthService.SignedIn signedIn) {
        return new SignedIn(signedIn.token(), toSession(signedIn.member(), signedIn.deviceId()));
    }

    Group toApi(GroupInfo info) {
        Group group = new Group(info.id(), info.name(), info.position(), info.memberIds());
        group.setIconToken(info.iconToken());
        return group;
    }

    Device toApi(DeviceRepository.DeviceRow row, UUID currentDeviceId) {
        Device device =
                new Device(
                        row.id(),
                        row.memberId(),
                        row.name(),
                        platform(row.platform()),
                        row.createdAt(),
                        row.id().equals(currentDeviceId));
        device.setLastSeenAt(row.lastSeenAt());
        device.setLastSyncSeq(row.lastSyncSeq());
        device.setPendingCount(row.pendingCount());
        device.setStaySignedIn(row.staySignedIn());
        return device;
    }

    /** How a device introduces itself, as the services take it. */
    static AuthService.NewDevice newDevice(DeviceRegistration registration) {
        return new AuthService.NewDevice(
                registration.getDeviceName(),
                registration.getPlatform().getValue(),
                !Boolean.FALSE.equals(registration.getStaySignedIn()),
                registration.getInstallationId());
    }

    /**
     * With {@code code} only in the answer to the creation: afterwards only its hash is
     * stored, and the list goes out without code and deep link.
     */
    Invitation toApi(InvitationRepository.InvitationRow row, String code, String host) {
        Invitation invitation = new Invitation(row.id(), row.expiresAt());
        if (code != null) {
            invitation.setCode(code);
            invitation.setDeepLink(deepLink(host, code));
        }
        invitation.setDisplayName(row.displayName());
        invitation.setGroupIds(row.groupIds());
        invitation.setRedeemedAt(row.redeemedAt());
        return invitation;
    }

    /**
     * The content of the QR code.
     *
     * <p>The {@code hiwiski://} scheme has to be registered in every platform project; in
     * an earlier version exactly that was missing. {@code host} carries the scheme
     * ({@code https://nas.example}), percent-encoded.
     */
    static String deepLink(String host, String code) {
        return "hiwiski://invite?host=" + URLEncoder.encode(host, StandardCharsets.UTF_8) + "&code=" + code;
    }

    /** Unknown tokens fall back to a default instead of costing the response. */
    static ColorToken colorToken(String value) {
        for (ColorToken token : ColorToken.values()) {
            if (token.getValue().equals(value)) {
                return token;
            }
        }
        return ColorToken.SLATE;
    }

    static AppearanceMode appearance(String value) {
        for (AppearanceMode mode : AppearanceMode.values()) {
            if (mode.getValue().equals(value)) {
                return mode;
            }
        }
        return AppearanceMode.SYSTEM;
    }

    static DevicePlatform platform(String value) {
        for (DevicePlatform platform : DevicePlatform.values()) {
            if (platform.getValue().equals(value)) {
                return platform;
            }
        }
        return DevicePlatform.UNKNOWN;
    }

    static List<UUID> orEmpty(List<UUID> values) {
        return values == null ? List.of() : values;
    }
}
