package de.danielkononov.hiwiski.admin.internal;

import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpInputMessage;
import org.springframework.http.HttpOutputMessage;
import org.springframework.http.MediaType;
import org.springframework.http.converter.AbstractHttpMessageConverter;
import org.springframework.http.converter.HttpMessageConverters;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * A raw upload body is a stream, never a byte array in the heap.
 *
 * <p>The generated interface takes an uploaded archive as a {@link Resource}, and
 * Spring's own converter reads a {@code Resource} into memory whole -- an archive with
 * years of photos, gigabytes, on a server with a small heap. This one hands over the
 * request's stream; the controller copies it to disk.
 */
@Configuration(proxyBeanMethods = false)
// Only with a web server: a maintenance command starts without one (CommandModeIT).
@ConditionalOnWebApplication
class StreamedUploads implements WebMvcConfigurer {

    @Override
    public void configureMessageConverters(HttpMessageConverters.ServerBuilder converters) {
        // Custom ones come before the defaults.
        converters.addCustomConverter(new Streamed());
    }

    private static final class Streamed extends AbstractHttpMessageConverter<Resource> {

        Streamed() {
            super(MediaType.APPLICATION_OCTET_STREAM);
        }

        @Override
        protected boolean supports(Class<?> type) {
            return Resource.class == type;
        }

        @Override
        protected boolean canWrite(MediaType mediaType) {
            return false;
        }

        @Override
        protected Resource readInternal(Class<? extends Resource> type, HttpInputMessage input) throws java.io.IOException {
            return new InputStreamResource(input.getBody());
        }

        @Override
        protected void writeInternal(Resource resource, HttpOutputMessage output) {
            throw new UnsupportedOperationException("reads only");
        }
    }
}
