package de.danielkononov.hiwiski.platform.internal;

import java.io.IOException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.resource.PathResourceResolver;

/**
 * Deep links into the web client load the application.
 *
 * <p>The client uses paths instead of {@code #}: the dashboard address is
 * {@code …/board/<token>} and is <strong>typed in by hand</strong> on a wall tablet
 * — a {@code /#/} in it is a source of errors nobody needs.
 *
 * <p>For that to work, the server has to answer every path it does not know with the
 * {@code index.html}. Otherwise a typed-in {@code /board/abc} would find no file and end
 * in 404 — the app would never load and could not resolve the address either.
 *
 * <p><strong>Not for {@code /api} and {@code /ics}.</strong> There a 404 is the right
 * answer; an HTML page in response to an API call would be an hour of debugging.
 *
 * <p><strong>{@code no-cache}</strong>: the browser asks again every time and gets a 304
 * while nothing changed. Flutter's files carry no hash in their names; without it a
 * browser kept {@code main.dart.js} by its own reckoning and "Reload" after an update
 * could start the old app against the new server. {@code build.json} says which build
 * is served, and the client offers that reload when it differs.
 *
 * <p><strong>"Nothing changed" is decided by the content, not by the date</strong>
 * ({@link WebClientEtags}): the files of every release carry the same date, so a
 * browser asking by date kept the web client of the release it had loaded first.
 */
@Configuration
// Only with a web server: a maintenance command starts without one (CommandModeIT).
@ConditionalOnWebApplication
class WebClientRouting implements WebMvcConfigurer {

    private final WebClientEtags etags = new WebClientEtags();

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/**")
                .addResourceLocations("classpath:/static/")
                .setCacheControl(CacheControl.noCache())
                // No date at all, rather than a date beside the tag: a browser that
                // still holds a copy from a server that answered by date asks by that
                // date once more, and has to get the file instead of "not modified".
                .setUseLastModified(false)
                .setEtagGenerator(etags::of)
                // No resolver cache: it is a map without a limit, and the fallback below
                // answers every made-up path, so `/a1`, `/a2`, … each added an entry for
                // good -- an unauthenticated way to fill the heap. The files are few and
                // looked up quickly.
                .resourceChain(false)
                .addResolver(new PathResourceResolver() {
                    @Override
                    protected Resource getResource(String path, Resource location) throws IOException {
                        // Spring's own lookup first: it checks that what it found
                        // lies inside the location, the second line against a path
                        // that climbs out of it.
                        Resource requested = super.getResource(path, location);
                        if (requested != null) {
                            return requested;
                        }
                        if (path.startsWith("api/") || path.startsWith("ics/") || path.startsWith("actuator/")) {
                            return null;
                        }
                        // A path the client resolves: load the application and let it
                        // decide.
                        Resource index = location.createRelative("index.html");
                        return index.exists() ? index : null;
                    }
                });
    }
}
