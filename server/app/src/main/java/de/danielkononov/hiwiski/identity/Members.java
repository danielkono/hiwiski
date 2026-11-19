package de.danielkononov.hiwiski.identity;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/** What other modules may know about members. */
public interface Members {

    Optional<MemberInfo> find(UUID id);

    List<MemberInfo> all();

    /** The groups this member is in. The basis of every share resolution. */
    List<UUID> groupsOf(UUID memberId);

    /** The member with {@code is_admin}. There is exactly one. */
    Optional<MemberInfo> administrator();
}
