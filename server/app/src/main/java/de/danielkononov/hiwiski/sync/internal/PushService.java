package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.api.model.Mutation;
import de.danielkononov.hiwiski.api.model.MutationResult;
import de.danielkononov.hiwiski.api.model.MutationStatus;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.SyncField;
import java.time.DateTimeException;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

/**
 * The write path: one mutation after the other.
 *
 * <p>The loop lives here, the transaction in {@link MutationApplier} -- a call within the
 * same class would bypass the proxy, and each mutation should have its own bracket.
 *
 * <p>The order is the client's. Its outbox knows the dependencies (a task created
 * offline in a list created offline), and the server relies on that instead of guessing
 * them again.
 */
@Service
class PushService {

    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    private final MutationApplier applier;

    PushService(MutationApplier applier) {
        this.applier = applier;
    }

    List<MutationResult> apply(List<Mutation> mutations, CurrentUser.Principal principal) {
        List<MutationResult> results = new ArrayList<>(mutations.size());
        for (Mutation mutation : mutations) {
            results.add(applyOne(mutation, principal));
        }
        return results;
    }

    /**
     * <strong>A mutation that fails does not drag the others down with it.</strong>
     *
     * <p>A push carries a batch — a task created offline, its list, a check mark. If one
     * of them hits a database constraint, the call must not end in a 500: the device
     * would then know of <em>no</em> mutation whether it went through, and would send
     * everything again next time.
     *
     * <p>Noticed in an acceptance test: a second dashboard violates
     * {@code board_one_per_kind} — and the whole push came back as a server error. Now
     * exactly this one mutation comes back as {@code rejected}, and the UI can say why.
     */
    private MutationResult applyOne(Mutation mutation, CurrentUser.Principal principal) {
        try {
            return applier.applyOne(mutation, principal);
        } catch (DataIntegrityViolationException e) {
            // Without the exception: Postgres names the failing row in its message --
            // the title, the text, a subscription's address -- and the log holds ids,
            // never content. The SQL state says which kind of constraint it was.
            log.info("mutation {} violates a constraint (SQL state {})", mutation.getMutationId(), sqlState(e));
            return rejected(mutation, "sync.constraint_violated");
        } catch (HiwiskiException e) {
            // A domain error from a module -- that too belongs to the mutation, not to
            // the call.
            log.info("mutation {} rejected: {}", mutation.getMutationId(), e.code());
            return rejected(mutation, e.code());
        } catch (IllegalArgumentException | ClassCastException | DateTimeException e) {
            // A value a module's own rule could not read -- a malformed ID in a refusal,
            // a field of the wrong type. Bad input, so it belongs to this mutation; a
            // 500 would block the device's outbox for good. Anything else (a lost
            // connection, a bug) still fails the call: rejecting it would make the
            // device drop a change that may well go through on the next try.
            // The exception's class only: its message may quote the value.
            log.info(
                    "mutation {} carries a value that cannot be read ({})",
                    mutation.getMutationId(),
                    e.getClass().getSimpleName());
            return rejected(mutation, SyncField.INVALID_FIELD);
        }
    }

    private static String sqlState(Throwable error) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause instanceof java.sql.SQLException sql && sql.getSQLState() != null) {
                return sql.getSQLState();
            }
        }
        return "unknown";
    }

    private static MutationResult rejected(Mutation mutation, String code) {
        MutationResult result = new MutationResult(mutation.getMutationId(), MutationStatus.REJECTED);
        result.setEntityId(mutation.getEntityId());
        result.setCode(code);
        return result;
    }
}
