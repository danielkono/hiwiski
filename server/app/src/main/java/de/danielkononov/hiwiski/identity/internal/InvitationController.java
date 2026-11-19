package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.InvitationsApi;
import de.danielkononov.hiwiski.api.model.CreateInvitationRequest;
import de.danielkononov.hiwiski.api.model.Invitation;
import de.danielkononov.hiwiski.api.model.InvitationList;
import de.danielkononov.hiwiski.api.model.InvitationPreview;
import de.danielkononov.hiwiski.api.model.RedeemInvitationRequest;
import de.danielkononov.hiwiski.api.model.SignedIn;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.CurrentRequest;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class InvitationController implements InvitationsApi {

    private final InvitationService invitations;
    private final IdentityMapper mapper;

    InvitationController(
            InvitationService invitations, IdentityMapper mapper) {
        this.invitations = invitations;
        this.mapper = mapper;
    }

    /**
     * Administrator only, like creating one: the list carries the codes, and a code is
     * a family account in the invitation's groups for whoever redeems it first.
     */
    @Override
    public ResponseEntity<InvitationList> listInvitations() {
        CurrentUser.require().requireAdmin();
        // Without their codes: only the hash is stored (the code goes out once, below).
        var list = invitations.open().stream().map(row -> mapper.toApi(row, null, null)).toList();
        return ResponseEntity.ok(new InvitationList(list));
    }

    @Override
    public ResponseEntity<Invitation> createInvitation(CreateInvitationRequest body) {
        var principal = CurrentUser.require();
        principal.requireAdmin();
        var created =
                invitations.create(
                        principal.memberId(),
                        body.getDisplayName(),
                        IdentityMapper.orEmpty(body.getGroupIds()),
                        body.getValidity().getValue());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(mapper.toApi(created.invitation(), created.code(), host()));
    }

    @Override
    public ResponseEntity<InvitationPreview> previewInvitation(String code) {
        var preview = invitations.preview(code, ClientAddress.current());
        InvitationPreview body =
                new InvitationPreview(preview.familyName(), preview.invitedBy(), preview.expiresAt());
        body.setDisplayName(preview.displayName());
        body.setGroupNames(preview.groupNames());
        return ResponseEntity.ok(body);
    }

    @Override
    public ResponseEntity<SignedIn> redeemInvitation(String code, RedeemInvitationRequest body) {
        var signedIn =
                invitations.redeem(
                        code,
                        body.getMemberId(),
                        body.getDisplayName(),
                        body.getUsername(),
                        body.getPassword(),
                        IdentityMapper.newDevice(body.getDevice()),
                        ClientAddress.current());
        return ResponseEntity.status(HttpStatus.CREATED).body(mapper.toSignedIn(signedIn));
    }

    /** Administrator only, like creating one. */
    @Override
    public ResponseEntity<Void> revokeInvitation(UUID id) {
        CurrentUser.require().requireAdmin();
        invitations.revoke(id);
        return ResponseEntity.noContent().build();
    }

    /**
     * The address under which this server was reached, with its scheme.
     *
     * <p>It goes into the QR code's deep link, exactly as the inviting device reached the
     * server: a fixed, configured name would often be the wrong one on a home network.
     *
     * <p>The scheme too: without it the joining device assumed {@code http://}, and on a
     * server with TLS the new member's password and from then on the device token went
     * over the wire in plain text. It is the scheme Tomcat settled on -- behind Caddy
     * the one {@code X-Forwarded-Proto} names, believed only from a trusted proxy.
     */
    private String host() {
        var request = CurrentRequest.get();
        String forwarded = request.getHeader("X-Forwarded-Host");
        String host;
        if (forwarded != null && !forwarded.isBlank()) {
            host = forwarded.split(",")[0].trim();
        } else {
            String header = request.getHeader("Host");
            host = (header == null || header.isBlank()) ? request.getServerName() : header;
        }
        // Both headers are the caller's to write. What goes into the link is a name or
        // an address with an optional port -- nothing that could carry a path, a user
        // or a second host into the QR code.
        if (!HOST.matcher(host).matches()) {
            host = request.getServerName();
        }
        return request.getScheme() + "://" + host;
    }

    private static final java.util.regex.Pattern HOST =
            java.util.regex.Pattern.compile("(\\[[0-9A-Fa-f:.]+\\]|[A-Za-z0-9.-]{1,253})(:[0-9]{1,5})?");
}
