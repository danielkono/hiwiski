package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.MembersApi;
import de.danielkononov.hiwiski.api.model.CreateMemberRequest;
import de.danielkononov.hiwiski.api.model.Member;
import de.danielkononov.hiwiski.api.model.MemberList;
import de.danielkononov.hiwiski.api.model.PasswordReset;
import de.danielkononov.hiwiski.api.model.UpdateMemberRequest;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class MemberController implements MembersApi {

    private final MemberService members;
    private final AuthService auth;
    private final IdentityMapper mapper;

    MemberController(MemberService members, AuthService auth, IdentityMapper mapper) {
        this.members = members;
        this.auth = auth;
        this.mapper = mapper;
    }

    @Override
    public ResponseEntity<MemberList> listMembers() {
        CurrentUser.require();
        var list = members.all().stream()
                .map(info -> members.row(info.id()).orElseThrow())
                .map(mapper::toApi)
                .toList();
        return ResponseEntity.ok(new MemberList(list));
    }

    @Override
    public ResponseEntity<Member> createMember(CreateMemberRequest request) {
        CurrentUser.require().requireAdmin();
        var created =
                members.create(
                        request.getDisplayName(),
                        request.getUsername(),
                        request.getPassword(),
                        request.getColorToken() == null ? null : request.getColorToken().getValue(),
                        IdentityMapper.orEmpty(request.getGroupIds()),
                        false);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(mapper.toApi(members.row(created.id()).orElseThrow()));
    }

    /**
     * Everyone themselves; the administrator everyone.
     *
     * <p>This is not an exception to the principle "the administrator may not touch other
     * people's content": display name and color are not content, and whoever creates a
     * member must also be able to name them.
     */
    @Override
    public ResponseEntity<Member> updateMember(UUID id, UpdateMemberRequest request) {
        var principal = CurrentUser.require();
        if (!principal.memberId().equals(id) && !principal.admin()) {
            throw HiwiskiException.forbidden("identity.not_your_profile");
        }
        members.update(
                id,
                request.getDisplayName(),
                request.getColorToken() == null ? null : request.getColorToken().getValue(),
                request.getAppearance() == null ? null : request.getAppearance().getValue());
        if (Boolean.TRUE.equals(request.getRemoveAvatar())) {
            members.setAvatar(id, null);
        } else if (request.getAvatarImageId() != null) {
            members.setAvatar(id, request.getAvatarImageId());
        }
        return ResponseEntity.ok(mapper.toApi(members.row(id).orElseThrow()));
    }

    @Override
    public ResponseEntity<Member> disableMember(UUID id) {
        CurrentUser.require().requireAdmin();
        auth.disableMember(id);
        return ResponseEntity.ok(mapper.toApi(members.row(id).orElseThrow()));
    }

    @Override
    public ResponseEntity<Member> enableMember(UUID id) {
        CurrentUser.require().requireAdmin();
        auth.enableMember(id);
        return ResponseEntity.ok(mapper.toApi(members.row(id).orElseThrow()));
    }

    @Override
    public ResponseEntity<Void> signOutMember(UUID id) {
        CurrentUser.require().requireAdmin();
        auth.signOutMember(id);
        return ResponseEntity.noContent().build();
    }

    @Override
    public ResponseEntity<PasswordReset> resetMemberPassword(UUID id) {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.ok(new PasswordReset(auth.resetPassword(id)));
    }
}
