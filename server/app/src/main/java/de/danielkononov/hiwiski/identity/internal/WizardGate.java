package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.SetupGate;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import org.jspecify.annotations.Nullable;
import org.springframework.stereotype.Component;

@Component
class WizardGate implements SetupGate {

    private final SetupService setup;
    private final SetupCode code;
    private final MemberService members;
    private final SetupLock lock;

    WizardGate(SetupService setup, SetupCode code, MemberService members, SetupLock lock) {
        this.setup = setup;
        this.code = code;
        this.members = members;
        this.lock = lock;
    }

    @Override
    public void requireFreshAndHold() {
        lock.hold();
        requireFresh();
    }

    @Override
    public boolean completed() {
        return setup.completed();
    }

    @Override
    public void requireCode(@Nullable String given, String client) {
        code.require(given, client);
    }

    @Override
    public void requireFresh() {
        if (setup.completed() || members.anyMemberExists()) {
            throw HiwiskiException.conflict("setup.already_completed");
        }
    }

    @Override
    public String currentClient() {
        return ClientAddress.current();
    }
}
