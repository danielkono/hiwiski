package de.danielkononov.hiwiski.platform.internal;

import java.util.stream.Collectors;
import org.springframework.boot.context.properties.bind.validation.BindValidationException;
import org.springframework.boot.diagnostics.AbstractFailureAnalyzer;
import org.springframework.boot.diagnostics.FailureAnalysis;
import org.springframework.validation.ObjectError;

/**
 * Turns a failed configuration binding into a line that says which variable is missing.
 *
 * <p>"The server does not start when a mandatory variable is missing -- with an English
 * line that says which one. A server that comes up with half a configuration fails later
 * at a place that has nothing to do with the cause."
 *
 * <p>English, because this line is read by the person who runs the server.
 */
public class MissingConfigurationFailureAnalyzer extends AbstractFailureAnalyzer<BindValidationException> {

    @Override
    protected FailureAnalysis analyze(Throwable rootFailure, BindValidationException cause) {
        String fields =
                cause.getValidationErrors().getAllErrors().stream()
                        .map(MissingConfigurationFailureAnalyzer::describe)
                        .distinct()
                        .collect(Collectors.joining("\n  "));

        return new FailureAnalysis(
                "hiwiski is not configured completely:\n  " + fields,
                """
                Set the missing environment variables and start again. They are listed in \
                deploy/.env.example; every path is mandatory and has no default on purpose \
                — a path with a default is not a path that was set.""",
                cause);
    }

    private static String describe(ObjectError error) {
        String field =
                error instanceof org.springframework.validation.FieldError fieldError
                        ? fieldError.getField()
                        : error.getObjectName();
        return "hiwiski." + hyphenate(field) + " (" + environmentVariable(field) + ") " + error.getDefaultMessage();
    }

    private static String hyphenate(String camelCase) {
        return camelCase.replaceAll("([a-z])([A-Z])", "$1-$2").toLowerCase();
    }

    private static String environmentVariable(String camelCase) {
        return "HIWISKI_" + hyphenate(camelCase).replace('-', '_').toUpperCase();
    }
}
