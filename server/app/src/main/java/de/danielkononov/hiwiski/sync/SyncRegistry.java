package de.danielkononov.hiwiski.sync;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/** All registered entity types, looked up by their name in the contract. */
@Component
public class SyncRegistry {

    private final Map<String, SyncType> byName;

    SyncRegistry(List<SyncType> types) {
        this.byName = types.stream().collect(Collectors.toMap(SyncType::entityType, Function.identity()));
    }

    /**
     * Empty if this server does not know the type.
     *
     * <p>That is not an error but the normal case for a newer client against an older
     * server -- and it must yield a {@code rejected}, not a crash.
     */
    public Optional<SyncType> find(String entityType) {
        return Optional.ofNullable(byName.get(entityType));
    }

    public List<SyncType> all() {
        return List.copyOf(byName.values());
    }
}
