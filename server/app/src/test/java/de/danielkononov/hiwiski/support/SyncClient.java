package de.danielkononov.hiwiski.support;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/** A device that pushes and pulls -- just as the app does. */
public final class SyncClient {

    private final RestTestClient rest;
    private final Family.Session session;

    /** The position this device has seen. **Never** incremented locally. */
    private long lastSeq;

    public SyncClient(RestTestClient rest, Family.Session session) {
        this.rest = rest;
        this.session = session;
    }

    public long lastSeq() {
        return lastSeq;
    }

    public void setLastSeq(long value) {
        this.lastSeq = value;
    }

    /** A mutation as it sits in the outbox. */
    public static Map<String, Object> mutation(
            String entityType, UUID entityId, Long baseVersion, Map<String, Object> fields) {
        Map<String, Object> mutation = new LinkedHashMap<>();
        mutation.put("mutationId", UUID.randomUUID().toString());
        mutation.put("entityType", entityType);
        mutation.put("entityId", entityId.toString());
        mutation.put("op", "upsert");
        if (baseVersion != null) {
            mutation.put("baseVersion", baseVersion);
        }
        mutation.put("fields", fields);
        return mutation;
    }

    public static Map<String, Object> withContainer(
            Map<String, Object> mutation, String containerType, UUID containerId) {
        mutation.put("containerType", containerType);
        mutation.put("containerId", containerId.toString());
        return mutation;
    }

    public static Map<String, Object> deletion(String entityType, UUID entityId, Long baseVersion) {
        Map<String, Object> mutation = new LinkedHashMap<>();
        mutation.put("mutationId", UUID.randomUUID().toString());
        mutation.put("entityType", entityType);
        mutation.put("entityId", entityId.toString());
        mutation.put("op", "delete");
        if (baseVersion != null) {
            mutation.put("baseVersion", baseVersion);
        }
        return mutation;
    }

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> push(Map<String, Object>... mutations) {
        var body = rest.post()
                .uri("/api/v1/sync/push")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "deviceId", session.deviceId().toString(),
                        "pendingCount", mutations.length,
                        "mutations", List.of(mutations)))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return (List<Map<String, Object>>) body.get("results");
    }

    /** Pulls until nothing more comes -- just as the client does. */
    @SuppressWarnings("unchecked")
    /**
     * More pages than any test writes: a server that never stops answering "hasMore"
     * fails the test instead of hanging the build.
     */
    private static final int MAX_PAGES = 1000;

    private static void checkPages(int pages) {
        if (pages > MAX_PAGES) {
            throw new AssertionError("still hasMore after " + MAX_PAGES + " pages");
        }
    }

    public List<Map<String, Object>> pullAll() {
        List<Map<String, Object>> all = new ArrayList<>();
        for (int pages = 1; ; pages++) {
            checkPages(pages);
            var body = pullOnce();
            all.addAll((List<Map<String, Object>>) body.get("changes"));
            if (!Boolean.TRUE.equals(body.get("hasMore"))) {
                return all;
            }
        }
    }

    /**
     * The full snapshot, page by page -- just as a fresh device fetches it. Afterwards the
     * position is what the server knew when the snapshot began.
     */
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> pullSnapshot(int limit) {
        List<Map<String, Object>> all = new ArrayList<>();
        String cursor = null;
        for (int pages = 1; ; pages++) {
            checkPages(pages);
            Map<String, Object> request = new LinkedHashMap<>();
            request.put("lastSeq", 0);
            request.put("deviceId", session.deviceId().toString());
            request.put("pendingCount", 0);
            request.put("limit", limit);
            request.put("snapshot", true);
            if (cursor != null) {
                request.put("snapshotCursor", cursor);
            }
            var body = rest.post()
                    .uri("/api/v1/sync/pull")
                    .headers(session.auth())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .exchange()
                    .expectStatus()
                    .isOk()
                    .expectBody(Map.class)
                    .returnResult()
                    .getResponseBody();
            all.addAll((List<Map<String, Object>>) body.get("changes"));
            if (!Boolean.TRUE.equals(body.get("hasMore"))) {
                lastSeq = ((Number) body.get("latestSeq")).longValue();
                return all;
            }
            cursor = (String) body.get("snapshotCursor");
        }
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> pullOnce() {
        var body = rest.post()
                .uri("/api/v1/sync/pull")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "lastSeq", lastSeq,
                        "deviceId", session.deviceId().toString(),
                        "pendingCount", 0))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        Object latest = body.get("latestSeq");
        if (latest instanceof Number number) {
            lastSeq = number.longValue();
        }
        return (Map<String, Object>) body;
    }
}
