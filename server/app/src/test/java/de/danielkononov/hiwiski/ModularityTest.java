package de.danielkononov.hiwiski;

import com.tngtech.archunit.base.DescribedPredicate;
import com.tngtech.archunit.core.domain.JavaClass;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

/**
 * The module boundaries are not a statement of intent.
 *
 * <p>This test breaks as soon as a module reaches into another's internals or a cycle
 * appears. That makes it the only barrier that keeps the monolith from turning into a
 * tangle over time. Three dependencies can be built the wrong way round, and then you
 * never get rid of them:
 *
 * <ul>
 *   <li>{@code access} points to {@code sync}, not the other way round.
 *   <li>{@code platform} must not point to {@code access}.
 *   <li>The cross-cutting modules know no domain types -- the domain modules register
 *       themselves.
 * </ul>
 */
class ModularityTest {

    /**
     * {@code de.danielkononov.hiwiski.api} and {@code ….db.generated} contain the contract
     * generated from the spec and the schema. They live below {@code de.danielkononov.hiwiski}
     * only because the package prefix should match the rest. They are not domain modules:
     * they are generated, every controller implements an interface from them, and drawing
     * a boundary against them would make no sense.
     */
    static final DescribedPredicate<JavaClass> GENERATED_CONTRACT =
            JavaClass.Predicates.resideInAnyPackage(
                    "de.danielkononov.hiwiski.api..", "de.danielkononov.hiwiski.db.generated..");

    static final ApplicationModules MODULES =
            ApplicationModules.of(HiwiskiApplication.class, GENERATED_CONTRACT);

    @Test
    void moduleBoundariesHold() {
        MODULES.verify();
    }

    /**
     * Writes the verified boundaries as an overview to {@code build/spring-modulith-docs}
     * -- the only place where the picture is guaranteed to match the code.
     */
    @Test
    void writesDocumentation() {
        new Documenter(MODULES).writeDocumentation();
    }
}
