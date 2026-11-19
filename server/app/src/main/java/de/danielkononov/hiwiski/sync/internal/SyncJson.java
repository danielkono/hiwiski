package de.danielkononov.hiwiski.sync.internal;

import java.util.LinkedHashMap;
import java.util.Map;
import org.jooq.JSONB;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

/** JSONB from and to Java maps. */
@Component
class SyncJson {

    private static final TypeReference<Map<String, Object>> MAP = new TypeReference<>() {};

    private final ObjectMapper mapper;

    SyncJson(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    Map<String, Object> read(JSONB value) {
        if (value == null || value.data() == null || value.data().isBlank()) {
            return new LinkedHashMap<>();
        }
        return new LinkedHashMap<>(mapper.readValue(value.data(), MAP));
    }

    Map<String, Long> readSequences(JSONB value) {
        Map<String, Long> result = new LinkedHashMap<>();
        read(value).forEach((key, raw) -> {
            if (raw instanceof Number number) {
                result.put(key, number.longValue());
            }
        });
        return result;
    }

    JSONB write(Map<String, ?> value) {
        return JSONB.valueOf(mapper.writeValueAsString(value));
    }
}
