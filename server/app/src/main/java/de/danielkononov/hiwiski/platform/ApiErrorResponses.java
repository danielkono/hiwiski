package de.danielkononov.hiwiski.platform;

import tools.jackson.databind.ObjectMapper;
import de.danielkononov.hiwiski.api.model.ApiError;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

/**
 * The security chain, too, answers in the contract's error shape.
 *
 * <p>Without this, Spring Security falls back to its own responses: an empty body and,
 * for a request with no authentication at all, {@code 403}. The contract, however, says
 * {@code 401} for "not signed in" and {@code 403} for "not shared", and a
 * client that cannot tell the two apart does not know whether to show the login screen
 * or display a message.
 */
@Component
public class ApiErrorResponses implements AuthenticationEntryPoint, AccessDeniedHandler {

    private final ObjectMapper json;

    ApiErrorResponses(ObjectMapper json) {
        this.json = json;
    }

    @Override
    public void commence(
            HttpServletRequest request, HttpServletResponse response, AuthenticationException exception)
            throws IOException {
        write(response, HttpStatus.UNAUTHORIZED, "auth.required");
    }

    @Override
    public void handle(
            HttpServletRequest request, HttpServletResponse response, AccessDeniedException exception)
            throws IOException {
        write(response, HttpStatus.FORBIDDEN, "access.denied");
    }

    /**
     * The same error shape outside the security chain as well.
     *
     * <p>A filter does not pass the {@code RestControllerAdvice} -- it runs before it.
     * Without this route it would answer with an empty body, and the client would have
     * no code to translate.
     */
    public void write(HttpServletResponse response, HttpStatus status, String code) throws IOException {
        ApiError error = new ApiError(code);
        String correlationId = CorrelationId.get();
        if (correlationId != null) {
            error.setCorrelationId(correlationId);
        }
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        json.writeValue(response.getOutputStream(), error);
    }
}
