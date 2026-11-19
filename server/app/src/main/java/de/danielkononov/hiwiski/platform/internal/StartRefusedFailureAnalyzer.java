package de.danielkononov.hiwiski.platform.internal;

import de.danielkononov.hiwiski.platform.StartRefused;
import org.springframework.boot.diagnostics.AbstractFailureAnalyzer;
import org.springframework.boot.diagnostics.FailureAnalysis;

/** Says why the server did not start -- a backup directory it cannot write, a failed backup before an update. */
public class StartRefusedFailureAnalyzer extends AbstractFailureAnalyzer<StartRefused> {

    @Override
    protected FailureAnalysis analyze(Throwable rootFailure, StartRefused cause) {
        return new FailureAnalysis(cause.getMessage(), cause.action(), cause);
    }
}
