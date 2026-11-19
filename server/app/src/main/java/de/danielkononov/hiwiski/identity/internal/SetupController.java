package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.SetupApi;
import de.danielkononov.hiwiski.api.model.SetupRequest;
import de.danielkononov.hiwiski.api.model.SignedIn;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class SetupController implements SetupApi {

    private final SetupService setup;
    private final SetupCode setupCode;
    private final IdentityMapper mapper;

    SetupController(SetupService setup, SetupCode setupCode, IdentityMapper mapper) {
        this.setup = setup;
        this.setupCode = setupCode;
        this.mapper = mapper;
    }

    @Override
    public ResponseEntity<SignedIn> runSetup(SetupRequest request) {
        // Before anything else: an instance set up already answers 409 only to whoever
        // holds the code -- and without it nobody learns anything from this call.
        setupCode.require(request.getSetupCode(), ClientAddress.current());
        var signedIn =
                setup.run(
                        request.getFamilyName(),
                        request.getTimezone(),
                        request.getAdmin().getId(),
                        request.getAdmin().getDisplayName(),
                        request.getAdmin().getUsername(),
                        request.getAdmin().getPassword(),
                        request.getGroups(),
                        IdentityMapper.newDevice(request.getDevice()),
                        request.getLanguage(),
                        request.getBackupPassword());
        return ResponseEntity.status(HttpStatus.CREATED).body(mapper.toSignedIn(signedIn));
    }
}
