package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.GroupInfo;
import de.danielkononov.hiwiski.identity.GroupMembersChanged;
import de.danielkononov.hiwiski.identity.MemberInfo;
import de.danielkononov.hiwiski.identity.Members;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Stream;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import org.springframework.transaction.annotation.Transactional;

/** Members -- readable by everyone, writable by the rules. */
@Service
class MemberService implements Members {

    private final MemberRepository members;
    private final GroupRepository groups;
    private final PasswordEncoder passwords;
    private final ApplicationEventPublisher events;
    private final InstanceSettings settings;

    MemberService(
            MemberRepository members,
            GroupRepository groups,
            PasswordEncoder passwords,
            ApplicationEventPublisher events,
            InstanceSettings settings) {
        this.members = members;
        this.groups = groups;
        this.passwords = passwords;
        this.events = events;
        this.settings = settings;
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<MemberInfo> find(UUID id) {
        return members.find(id).map(MemberService::toInfo);
    }

    @Override
    @Transactional(readOnly = true)
    public List<MemberInfo> all() {
        return members.all().stream().map(MemberService::toInfo).toList();
    }

    @Override
    @Transactional(readOnly = true)
    public List<UUID> groupsOf(UUID memberId) {
        return members.groupsOf(memberId);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<MemberInfo> administrator() {
        return members.findAdministrator().map(MemberService::toInfo);
    }

    @Transactional
    MemberInfo create(
            String displayName,
            String username,
            String password,
            String colorToken,
            List<UUID> groupIds,
            boolean admin) {
        return create(null, displayName, username, password, colorToken, groupIds, admin);
    }

    /**
     * With the id the app brings ({@code requestedId}), or a new one when it brings none.
     *
     * <p>A device used without a server created its member there and wrote its id into
     * every item -- owner, assignees, attendees. Created under the same id, all of that
     * stays valid when the device connects. Members are never deleted, so
     * an id is taken for good once used.
     */
    @Transactional
    MemberInfo create(
            UUID requestedId,
            String displayName,
            String username,
            String password,
            String colorToken,
            List<UUID> groupIds,
            boolean admin) {
        requireGroups(groupIds);
        String normalized = normalizeUsername(username);
        if (members.usernameTaken(normalized)) {
            throw HiwiskiException.conflict("identity.username_taken", "username", normalized);
        }
        if (requestedId != null && members.find(requestedId).isPresent()) {
            throw HiwiskiException.conflict("identity.id_taken", "id", requestedId);
        }
        UUID id = requestedId == null ? UUID.randomUUID() : requestedId;
        members.insert(
                id,
                normalized,
                requireName(displayName),
                passwords.encode(requirePassword(password)),
                admin,
                colorToken == null ? "SLATE" : colorToken);
        List<UUID> joined = withDefaultGroup(groupIds);
        members.setGroups(id, joined);
        // A new member gets what was shared with their groups before they existed.
        events.publishEvent(new GroupMembersChanged(joined));
        return members.find(id).map(MemberService::toInfo).orElseThrow();
    }

    /**
     * Every new member goes into the first group.
     *
     * <p>During setup it is created as "Everyone". Without
     * this, a new member would be in no group, and every share with "Everyone" would pass
     * them by -- which nobody naming a group that way expects.
     */
    private List<UUID> withDefaultGroup(List<UUID> groupIds) {
        List<UUID> target = groupIds == null ? List.of() : groupIds;
        // The group the setup named, by ID -- not whichever comes first: after
        // "Everyone" was deleted or the groups reordered, the next child who redeemed an
        // invitation landed in "Parents" and got everything shared with it.
        Optional<GroupInfo> everyone = settings.find(SettingKey.DEFAULT_GROUP)
                .map(UUID::fromString)
                .flatMap(groups::find);
        if (everyone.isEmpty()) {
            return target;
        }
        return Stream.concat(Stream.of(everyone.get().id()), target.stream()).distinct().toList();
    }

    @Transactional
    MemberInfo update(UUID id, String displayName, String colorToken, String themeMode) {
        members.find(id)
                .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found", "memberId", id));
        // Left out means unchanged; given, a name has to be one -- as when the member
        // was created. A blank one showed them nameless in lists, share sheets and
        // invitation previews.
        members.updateProfile(id, displayName == null ? null : requireName(displayName), colorToken, themeMode);
        return members.find(id).map(MemberService::toInfo).orElseThrow();
    }

    /**
     * Sets the member's picture — an image uploaded with the member as its carrier, so
     * nobody hangs someone else's upload on their profile. {@code null} removes it.
     */
    @Transactional
    void setAvatar(UUID id, UUID imageId) {
        members.find(id)
                .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found", "memberId", id));
        if (imageId != null && !members.isOwnPicture(id, imageId)) {
            throw HiwiskiException.invalid("identity.avatar_invalid", "imageId", imageId);
        }
        members.setAvatar(id, imageId);
    }

    @Transactional
    void setGroups(UUID id, List<UUID> groupIds) {
        requireGroups(groupIds);
        List<UUID> before = members.groupsOf(id);
        members.setGroups(id, groupIds);
        // Left and joined alike: one loses access, the other gains it.
        events.publishEvent(new GroupMembersChanged(
                Stream.concat(before.stream(), groupIds.stream()).distinct().toList()));
    }

    @Transactional
    void setDisabled(UUID id, boolean disabled) {
        members.setDisabled(id, disabled);
    }

    @Transactional(readOnly = true)
    Optional<MemberRow> row(UUID id) {
        return members.find(id);
    }

    @Transactional(readOnly = true)
    Optional<MemberRow> rowByUsername(String username) {
        return members.findByUsername(username);
    }

    @Transactional
    void setPassword(UUID id, String rawPassword, boolean mustChange) {
        members.updatePassword(id, passwords.encode(requirePassword(rawPassword)), mustChange);
    }

    boolean passwordMatches(MemberRow member, String rawPassword) {
        // One longer than any that can be set matches none -- without hashing megabytes.
        return rawPassword != null
                && rawPassword.length() <= MAX_PASSWORD_LENGTH
                && passwords.matches(rawPassword, member.passwordHash());
    }

    /**
     * The longest a name may be, and a password. A request body may hold megabytes; a
     * display name that long went to every device with the member list, and a password
     * that long was hashed whole on every sign-in.
     */
    static final int MAX_NAME_LENGTH = 100;

    static final int MAX_PASSWORD_LENGTH = 1024;

    /** A text nobody has to be told about, cut to a name's length: a device's name. */
    static String shortened(String text) {
        return text.length() > MAX_NAME_LENGTH ? text.substring(0, MAX_NAME_LENGTH) : text;
    }

    /** {@code 400 identity.text_too_long} for a name beyond {@link #MAX_NAME_LENGTH}. */
    static String requireShort(String field, String text) {
        if (text.length() > MAX_NAME_LENGTH) {
            throw HiwiskiException.invalid(
                    "identity.text_too_long", "field", field, "maxLength", String.valueOf(MAX_NAME_LENGTH));
        }
        return text;
    }

    /** A hash nobody's password matches -- made once, on first use. */
    private volatile String decoy;

    /**
     * The same work as checking a password, for a username that does not exist.
     *
     * <p>Without it, "no such user" answered in a few milliseconds and a wrong password
     * after the full Argon2 check -- the timing listed every username and showed which
     * accounts are disabled.
     */
    void spendPasswordCheck(String rawPassword) {
        String hash = decoy;
        if (hash == null) {
            hash = decoy = passwords.encode(java.util.UUID.randomUUID().toString());
        }
        String given = rawPassword == null || rawPassword.length() > MAX_PASSWORD_LENGTH ? "" : rawPassword;
        passwords.matches(given, hash);
    }

    boolean anyMemberExists() {
        return members.any();
    }

    static String normalizeUsername(String username) {
        String normalized = username == null ? "" : username.trim().toLowerCase();
        if (!normalized.matches("[a-z0-9._-]{2,32}")) {
            throw HiwiskiException.invalid("identity.username_invalid", "username", normalized);
        }
        return normalized;
    }

    /**
     * Eight characters.
     *
     * <p>No special-character rule: it forces sticky notes on the screen and does not make
     * passwords better. The protection lies in Argon2id and the delay after failed
     * attempts.
     */
    private static String requirePassword(String password) {
        if (password == null || password.length() < 8) {
            throw HiwiskiException.invalid("identity.password_too_short", "minLength", "8");
        }
        if (password.length() > MAX_PASSWORD_LENGTH) {
            throw HiwiskiException.invalid(
                    "identity.text_too_long", "field", "password", "maxLength", String.valueOf(MAX_PASSWORD_LENGTH));
        }
        return password;
    }

    private static String requireName(String displayName) {
        if (displayName == null || displayName.isBlank()) {
            throw HiwiskiException.invalid("identity.display_name_required");
        }
        return requireShort("displayName", displayName.trim());
    }

    static MemberInfo toInfo(MemberRow row) {
        return new MemberInfo(
                row.id(),
                row.username(),
                row.displayName(),
                row.isAdmin(),
                row.colorToken(),
                row.groupIds(),
                row.createdAt().toInstant(),
                row.disabled());
    }

    /** Unknown group IDs are the request's mistake, not a foreign key's 500. */
    private void requireGroups(List<UUID> groupIds) {
        if (groupIds == null) {
            return;
        }
        for (UUID id : groupIds) {
            if (groups.find(id).isEmpty()) {
                throw HiwiskiException.invalid("identity.group_not_found", "groupId", id);
            }
        }
    }
}
