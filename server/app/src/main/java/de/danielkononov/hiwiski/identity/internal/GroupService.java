package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.GroupInfo;
import de.danielkononov.hiwiski.identity.GroupDeleted;
import de.danielkononov.hiwiski.identity.GroupMembersChanged;
import de.danielkononov.hiwiski.identity.Groups;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import org.springframework.transaction.annotation.Transactional;

/** Groups -- recipients of a share, not carriers of permissions. */
@Service
class GroupService implements Groups {

    private final GroupRepository groups;
    private final ApplicationEventPublisher events;
    private final InstanceSettings settings;
    private final MemberRepository members;

    GroupService(
            GroupRepository groups,
            ApplicationEventPublisher events,
            InstanceSettings settings,
            MemberRepository members) {
        this.groups = groups;
        this.events = events;
        this.settings = settings;
        this.members = members;
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<GroupInfo> find(UUID id) {
        return groups.find(id);
    }

    @Override
    @Transactional(readOnly = true)
    public List<GroupInfo> all() {
        return groups.all();
    }

    @Override
    @Transactional(readOnly = true)
    public List<UUID> membersOf(UUID groupId) {
        return groups.membersOf(groupId);
    }

    @Transactional
    GroupInfo create(String name, String iconToken, List<UUID> memberIds) {
        UUID id = groups.insert(UUID.randomUUID(), requireName(name), iconToken, groups.nextPosition());
        if (memberIds != null) {
            requireMembers(memberIds);
            groups.setMembers(id, memberIds);
            events.publishEvent(new GroupMembersChanged(List.of(id)));
        }
        return groups.find(id).orElseThrow();
    }

    @Transactional
    GroupInfo update(UUID id, String name, String iconToken, List<UUID> memberIds) {
        groups.find(id).orElseThrow(() -> HiwiskiException.notFound("identity.group_not_found", "groupId", id));
        groups.update(id, requireName(name), iconToken);
        if (memberIds != null) {
            requireMembers(memberIds);
            groups.setMembers(id, memberIds);
            events.publishEvent(new GroupMembersChanged(List.of(id)));
        }
        return groups.find(id).orElseThrow();
    }

    /**
     * The members stay; the memberships go with it.
     *
     * <p>Shares to this group disappear as well -- that comes up once {@code share}
     * exists. What goes along on delete belongs in an explicit list and in a test.
     */
    @Transactional
    void delete(UUID id) {
        groups.find(id).orElseThrow(() -> HiwiskiException.notFound("identity.group_not_found", "groupId", id));
        // The group every new member joins stays: without it, a share with "Everyone"
        // would pass every future member by.
        if (settings.find(SettingKey.DEFAULT_GROUP).filter(id.toString()::equals).isPresent()) {
            throw HiwiskiException.invalid("identity.group_default", "groupId", id);
        }
        groups.delete(id);
        // Its shares go with it, and what they granted is taken away again. Left behind,
        // a share row still counted as the item's own share: a page shared only with the
        // deleted group no longer fell back to its parent's audience, and the share sheet
        // listed a group that did not exist.
        events.publishEvent(new GroupDeleted(id));
    }

    private static String requireName(String name) {
        if (name == null || name.isBlank()) {
            throw HiwiskiException.invalid("identity.group_name_required");
        }
        return MemberService.requireShort("name", name.trim());
    }

    /** Unknown member IDs are the request's mistake, not a foreign key's 500. */
    private void requireMembers(List<UUID> memberIds) {
        for (UUID id : memberIds) {
            if (members.find(id).isEmpty()) {
                throw HiwiskiException.invalid("identity.member_not_found", "memberId", id);
            }
        }
    }
}
