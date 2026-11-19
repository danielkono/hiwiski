package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.MemberInfo;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.time.Clock;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Invitations with code and QR.
 *
 * <p>Only the code's hash is stored; the code itself goes out once, in the answer to its
 * creation. The preview and the redemption, open without an account, are counted per
 * client address: ten codes that match nothing are free, then one every thirty
 * seconds -- a valid one costs nothing.
 */
@Service
class InvitationService {

    /** Codes that match nothing, free per client address. */
    static final int CLIENT_CAPACITY = 10;

    /** After those, one more every so often. */
    static final Duration CLIENT_REFILL = Duration.ofSeconds(30);

    private final InvitationRepository invitations;
    private final MemberService members;
    private final GroupService groups;
    private final AuthService auth;
    private final Secrets secrets;
    private final InvitationCodeHash codeHash;
    private final InstanceSettings settings;
    private final ClientBudget clients =
            new ClientBudget("auth.too_many_attempts", CLIENT_CAPACITY, CLIENT_REFILL, Clock.systemUTC());

    InvitationService(
            InvitationRepository invitations,
            MemberService members,
            GroupService groups,
            AuthService auth,
            Secrets secrets,
            InvitationCodeHash codeHash,
            InstanceSettings settings) {
        this.invitations = invitations;
        this.members = members;
        this.groups = groups;
        this.auth = auth;
        this.secrets = secrets;
        this.codeHash = codeHash;
        this.settings = settings;
    }

    record Preview(
            String familyName, String invitedBy, String displayName, List<String> groupNames, OffsetDateTime expiresAt) {}

    /** A new invitation and its code -- the only time the code is known. */
    record Created(InvitationRepository.InvitationRow invitation, String code) {}

    @Transactional
    Created create(UUID createdBy, String displayName, List<UUID> groupIds, String validity) {

        String code = uniqueCode();
        UUID id = UUID.randomUUID();
        invitations.insert(
                id,
                codeHash.hash(code),
                displayName == null || displayName.isBlank() ? null : displayName.trim(),
                groupIds == null ? List.of() : groupIds,
                createdBy,
                OffsetDateTime.now().plus(duration(validity)));
        return new Created(invitations.find(id).orElseThrow(), code);
    }

    /**
     * A code no open invitation has.
     *
     * <p>Seven characters from an alphabet of 31 are about 27 billion possibilities -- a
     * collision is not to be expected at family size. Checked anyway: two open
     * invitations with one code would make the code open whichever is checked first,
     * over something a second roll solves.
     */
    private String uniqueCode() {
        var open = invitations.valid();
        for (int attempt = 0; attempt < 10; attempt++) {
            String code = secrets.newInvitationCode();
            if (open.stream().noneMatch(candidate -> codeHash.matches(code, candidate.codeHash()))) {
                return code;
            }
        }
        throw HiwiskiException.conflict("identity.invitation_code_exhausted");
    }

    List<InvitationRepository.InvitationRow> open() {
        return invitations.open();
    }

    /**
     * Withdraws an invitation nobody has redeemed: its code opens nothing from now on.
     *
     * <p>A redeemed one, or one that is gone, answers like a missing one: there is no
     * open invitation with this id to withdraw.
     */
    @Transactional
    void revoke(UUID id) {
        if (!invitations.deleteUnredeemed(id)) {
            throw HiwiskiException.notFound("identity.invitation_not_found");
        }
    }

    /**
     * The preview, without login.
     *
     * <p>Without this card nobody knows what they are joining.
     */
    @Transactional(readOnly = true)
    Preview preview(String code, String client) {
        var invitation = requireValid(code, client);
        String invitedBy =
                members.find(invitation.createdBy()).map(MemberInfo::displayName).orElse("—");
        List<String> groupNames =
                invitation.groupIds().stream()
                        .map(groups::find)
                        .flatMap(java.util.Optional::stream)
                        .map(group -> group.name())
                        .toList();
        return new Preview(
                settings.get(SettingKey.FAMILY_NAME, "hiwiski"),
                invitedBy,
                invitation.displayName(),
                groupNames,
                invitation.expiresAt());
    }

    @Transactional
    AuthService.SignedIn redeem(
            String code,
            UUID memberId,
            String displayName,
            String username,
            String password,
            AuthService.NewDevice device,
            String client) {

        var invitation = requireValid(code, client);

        // The groups that still exist: one deleted since the invitation was made would
        // break the membership's foreign key, and every redeem failed with a 500 until
        // the code expired.
        List<UUID> groupIds = invitation.groupIds() == null
                ? List.of()
                : invitation.groupIds().stream()
                        .filter(id -> groups.find(id).isPresent())
                        .toList();
        MemberInfo member = members.create(memberId, displayName, username, password, null, groupIds, false);

        // The condition is in the UPDATE: two devices redeeming the same code at the same
        // time would otherwise both get through, and the family would have two accounts
        // for one invitation.
        if (!invitations.redeem(invitation.id(), member.id())) {
            throw HiwiskiException.conflict("identity.invitation_already_redeemed");
        }

        MemberRow row = members.row(member.id()).orElseThrow();
        return auth.registerDevice(row, device);
    }

    /**
     * An expired or used code gets the same answer as a made-up one: {@code 404}.
     * Otherwise the difference would reveal that it existed.
     *
     * <p>Counted against the client before the lookup, and given back when the code is
     * valid: guessing codes runs into the budget, joining does not.
     *
     * <p>The code is checked against every open invitation, not only up to the one it
     * opens: a salted hash cannot be looked up (InvitationCodeHash).
     */
    private InvitationRepository.InvitationRow requireValid(String code, String client) {
        clients.spend(client);
        InvitationRepository.InvitationRow found = null;
        for (var candidate : invitations.valid()) {
            if (codeHash.matches(code, candidate.codeHash()) && found == null) {
                found = candidate.invitation();
            }
        }
        if (found == null) {
            throw HiwiskiException.notFound("identity.invitation_not_found");
        }
        clients.refund(client);
        return found;
    }

    static Duration duration(String validity) {
        return switch (validity == null ? "" : validity) {
            case "HOUR_1" -> Duration.ofHours(1);
            case "DAYS_7" -> Duration.ofDays(7);
            case "HOURS_24" -> Duration.ofHours(24);
            default -> throw HiwiskiException.invalid("identity.validity_invalid", "validity", String.valueOf(validity));
        };
    }

    /** Invalidate expired ones -- hourly. */
    @Scheduled(cron = "0 7 * * * *")
    @Transactional
    void removeExpired() {
        invitations.deleteExpired();
    }

    /** Clients whose budget has filled up again are forgotten. */
    @Scheduled(fixedDelay = 5 * 60 * 1000)
    void removeStaleClients() {
        clients.removeStale();
    }
}
