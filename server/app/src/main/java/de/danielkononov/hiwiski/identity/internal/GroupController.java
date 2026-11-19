package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.GroupsApi;
import de.danielkononov.hiwiski.api.model.Group;
import de.danielkononov.hiwiski.api.model.GroupList;
import de.danielkononov.hiwiski.api.model.WriteGroupRequest;
import de.danielkononov.hiwiski.identity.CurrentUser;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class GroupController implements GroupsApi {

    private final GroupService groups;
    private final IdentityMapper mapper;

    GroupController(GroupService groups, IdentityMapper mapper) {
        this.groups = groups;
        this.mapper = mapper;
    }

    @Override
    public ResponseEntity<GroupList> listGroups() {
        CurrentUser.require();
        return ResponseEntity.ok(new GroupList(groups.all().stream().map(mapper::toApi).toList()));
    }

    @Override
    public ResponseEntity<Group> createGroup(WriteGroupRequest request) {
        CurrentUser.require().requireAdmin();
        var group = groups.create(request.getName(), request.getIconToken(), request.getMemberIds());
        return ResponseEntity.status(HttpStatus.CREATED).body(mapper.toApi(group));
    }

    @Override
    public ResponseEntity<Group> updateGroup(UUID id, WriteGroupRequest request) {
        CurrentUser.require().requireAdmin();
        var group = groups.update(id, request.getName(), request.getIconToken(), request.getMemberIds());
        return ResponseEntity.ok(mapper.toApi(group));
    }

    @Override
    public ResponseEntity<Void> deleteGroup(UUID id) {
        CurrentUser.require().requireAdmin();
        groups.delete(id);
        return ResponseEntity.noContent().build();
    }
}
