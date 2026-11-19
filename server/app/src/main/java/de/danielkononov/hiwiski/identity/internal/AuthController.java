package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.AuthApi;
import de.danielkononov.hiwiski.api.model.ChangePasswordRequest;
import de.danielkononov.hiwiski.api.model.LoginRequest;
import de.danielkononov.hiwiski.api.model.Session;
import de.danielkononov.hiwiski.api.model.SignedIn;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class AuthController implements AuthApi {

    private final AuthService auth;
    private final MemberService members;
    private final IdentityMapper mapper;

    AuthController(AuthService auth, MemberService members, IdentityMapper mapper) {
        this.auth = auth;
        this.members = members;
        this.mapper = mapper;
    }

    @Override
    public ResponseEntity<SignedIn> login(LoginRequest request) {
        var signedIn =
                auth.login(
                        request.getUsername(),
                        request.getPassword(),
                        IdentityMapper.newDevice(request.getDevice()),
                        ClientAddress.current());
        return ResponseEntity.ok(mapper.toSignedIn(signedIn));
    }

    @Override
    public ResponseEntity<Void> logout() {
        var principal = CurrentUser.require();
        auth.logout(principal.memberId(), principal.deviceId());
        return ResponseEntity.noContent().build();
    }

    @Override
    public ResponseEntity<Session> getSession() {
        var principal = CurrentUser.require();
        MemberRow row =
                members.row(principal.memberId())
                        .orElseThrow(() -> HiwiskiException.notFound("identity.member_not_found"));
        return ResponseEntity.ok(mapper.toSession(row, principal.deviceId()));
    }

    @Override
    public ResponseEntity<Void> changePassword(ChangePasswordRequest request) {
        var principal = CurrentUser.require();
        auth.changePassword(
                principal.memberId(),
                principal.deviceId(),
                request.getCurrentPassword(),
                request.getNewPassword(),
                ClientAddress.current());
        return ResponseEntity.noContent().build();
    }
}
