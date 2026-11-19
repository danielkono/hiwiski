package de.danielkononov.hiwiski.identity;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/** What other modules may know about groups. */
public interface Groups {

    Optional<GroupInfo> find(UUID id);

    List<GroupInfo> all();

    List<UUID> membersOf(UUID groupId);
}
