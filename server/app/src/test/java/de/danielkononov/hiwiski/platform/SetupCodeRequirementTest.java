package de.danielkononov.hiwiski.platform;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** Off unless switched on -- and a fixed code switches it on. */
class SetupCodeRequirementTest {

    @Test
    void offByDefault() {
        assertThat(new SetupCodeRequirement(false, "").required()).isFalse();
        assertThat(new SetupCodeRequirement(false, null).required()).isFalse();
        assertThat(new SetupCodeRequirement(false, "   ").required()).as("a blank code is none").isFalse();
    }

    @Test
    void onWhenSwitchedOn() {
        assertThat(new SetupCodeRequirement(true, "").required()).isTrue();
    }

    /** An automated install that named a code before it became optional keeps its check. */
    @Test
    void onWithAFixedCode() {
        assertThat(new SetupCodeRequirement(false, "K7M4-2QXP").required()).isTrue();
    }
}
