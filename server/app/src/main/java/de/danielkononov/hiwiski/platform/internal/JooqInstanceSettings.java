package de.danielkononov.hiwiski.platform.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.INSTANCE_SETTING;

import de.danielkononov.hiwiski.platform.InstanceSettings;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class JooqInstanceSettings implements InstanceSettings {

    private final DSLContext db;

    JooqInstanceSettings(DSLContext db) {
        this.db = db;
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<String> find(String key) {
        return db.select(INSTANCE_SETTING.VALUE)
                .from(INSTANCE_SETTING)
                .where(INSTANCE_SETTING.KEY.eq(key))
                .fetchOptional(INSTANCE_SETTING.VALUE);
    }

    @Override
    public String get(String key, String fallback) {
        return find(key).orElse(fallback);
    }

    @Override
    public int getInt(String key, int fallback) {
        return find(key)
                .map(
                        value -> {
                            try {
                                return Integer.parseInt(value.trim());
                            } catch (NumberFormatException ignored) {
                                // A broken setting must not stop the server -- it
                                // falls back to the default.
                                return fallback;
                            }
                        })
                .orElse(fallback);
    }

    @Override
    public boolean getBoolean(String key, boolean fallback) {
        return find(key).map(Boolean::parseBoolean).orElse(fallback);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<String, String> all() {
        Map<String, String> result = new LinkedHashMap<>();
        db.select(INSTANCE_SETTING.KEY, INSTANCE_SETTING.VALUE)
                .from(INSTANCE_SETTING)
                .orderBy(INSTANCE_SETTING.KEY)
                .forEach(row -> result.put(row.value1(), row.value2()));
        return result;
    }

    @Override
    @Transactional
    public void put(String key, String value, UUID actor) {
        db.insertInto(INSTANCE_SETTING)
                .set(INSTANCE_SETTING.KEY, key)
                .set(INSTANCE_SETTING.VALUE, value)
                .set(INSTANCE_SETTING.UPDATED_BY, actor)
                .onConflict(INSTANCE_SETTING.KEY)
                .doUpdate()
                .set(INSTANCE_SETTING.VALUE, value)
                .set(INSTANCE_SETTING.UPDATED_AT, org.jooq.impl.DSL.currentOffsetDateTime())
                .set(INSTANCE_SETTING.UPDATED_BY, actor)
                .execute();
    }

    @Override
    @Transactional
    public void putAll(Map<String, String> values, UUID actor) {
        values.forEach((key, value) -> put(key, value, actor));
    }

    @Override
    public void remove(String key) {
        db.deleteFrom(INSTANCE_SETTING).where(INSTANCE_SETTING.KEY.eq(key)).execute();
    }
}
