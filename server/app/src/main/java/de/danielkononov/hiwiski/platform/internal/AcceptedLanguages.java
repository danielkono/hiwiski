package de.danielkononov.hiwiski.platform.internal;

import org.springframework.boot.tomcat.servlet.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.stereotype.Component;

/**
 * How many languages a request may name in its {@code Accept-Language}.
 *
 * <p>Tomcat refuses more than ten, and the request then fails as a whole: Spring reads
 * the request's language for every request, so the page and every call of the API
 * answered 500. A phone set up with many languages sends more than ten -- a Samsung
 * browser did -- and could not use the server at all. The header's length stays
 * limited by Tomcat's maximum header size, so a generous count costs nothing.
 */
@Component
class AcceptedLanguages implements WebServerFactoryCustomizer<TomcatServletWebServerFactory> {

    /** Far more than any browser or phone sends. */
    static final int MAX_LANGUAGES = 100;

    @Override
    public void customize(TomcatServletWebServerFactory factory) {
        factory.addConnectorCustomizers(connector -> connector.setMaxLocaleCount(MAX_LANGUAGES));
    }
}
