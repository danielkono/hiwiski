package de.danielkononov.hiwiski.platform.internal;

import de.danielkononov.hiwiski.api.model.ApiError;
import de.danielkononov.hiwiski.platform.CorrelationId;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

/**
 * Translates exceptions into the contract's error shape: code plus parameters.
 *
 * <p>There is <strong>no</strong> German sentence here. The message the user reads is
 * built by the client from the code and its ARB files.
 */
@RestControllerAdvice
class ErrorAdvice {

    private static final Logger log = LoggerFactory.getLogger(ErrorAdvice.class);

    @ExceptionHandler(HiwiskiException.class)
    ResponseEntity<ApiError> onHiwiski(HiwiskiException exception) {
        // Domain errors are the normal case and no reason for a stack trace.
        log.debug("rejected: {} {}", exception.code(), exception.params());
        var response = ResponseEntity.status(exception.status());
        String retryAfter = exception.params().get(HiwiskiException.RETRY_AFTER_SECONDS);
        if (retryAfter != null) {
            response.header(org.springframework.http.HttpHeaders.RETRY_AFTER, retryAfter);
        }
        return response.body(body(exception.code(), exception.params()));
    }

    @ExceptionHandler({
        MethodArgumentNotValidException.class,
        ConstraintViolationException.class,
        HttpMessageNotReadableException.class,
        IllegalArgumentException.class,
        org.springframework.beans.TypeMismatchException.class
    })
    ResponseEntity<ApiError> onInvalid(Exception exception) {
        log.debug("invalid request", exception);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body("request.invalid", null));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ApiError> onDenied(AccessDeniedException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(body("access.denied", null));
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ResponseEntity<ApiError> onTooLarge(MaxUploadSizeExceededException exception) {
        return ResponseEntity.status(HttpStatus.CONTENT_TOO_LARGE).body(body("request.too_large", null));
    }

    /**
     * The other side is gone — usually an event stream whose tab was closed.
     *
     * <p>Not an error, so no stack trace, and no response either: there is nobody left to
     * read it, and trying to write one only throws a second time. Previously this showed
     * up in the log every 25 seconds, per closed tab.
     */
    @ExceptionHandler(AsyncRequestNotUsableException.class)
    void onClientGone(AsyncRequestNotUsableException exception) {
        log.debug("client gone: {}", exception.getMessage());
    }

    /**
     * Everything else.
     *
     * <p>With stack trace into the log, with correlation ID to the client -- and without
     * content: personal data and titles do not go into the log.
     */
    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiError> onUnexpected(Exception exception) {
        if (exception instanceof org.springframework.web.ErrorResponse framework) {
            // Spring's own answers -- no such path, wrong method, missing parameter,
            // wrong content type. They are the request's fault, not the server's: as a
            // 500 with a stack trace each one flooded the admin log and hid real errors.
            log.debug("request refused: {}", exception.getMessage());
            var status = framework.getStatusCode();
            return ResponseEntity.status(status).body(body(codeOf(status.value()), null));
        }
        log.error("unhandled exception", exception);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(body("server.error", null));
    }

    private static String codeOf(int status) {
        return switch (status) {
            case 404 -> "request.not_found";
            case 405 -> "request.method_not_allowed";
            case 406, 415 -> "request.media_type";
            default -> "request.invalid";
        };
    }

    private static ApiError body(String code, java.util.Map<String, String> params) {
        ApiError error = new ApiError(code);
        if (params != null && !params.isEmpty()) {
            error.setParams(params);
        }
        String correlationId = CorrelationId.get();
        if (correlationId != null) {
            error.setCorrelationId(correlationId);
        }
        return error;
    }
}
