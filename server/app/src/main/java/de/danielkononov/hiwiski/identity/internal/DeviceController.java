package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.api.DevicesApi;
import de.danielkononov.hiwiski.api.model.DeviceList;
import de.danielkononov.hiwiski.identity.CurrentUser;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class DeviceController implements DevicesApi {

    private final DeviceRepository devices;
    private final AuthService auth;
    private final IdentityMapper mapper;

    DeviceController(DeviceRepository devices, AuthService auth, IdentityMapper mapper) {
        this.devices = devices;
        this.auth = auth;
        this.mapper = mapper;
    }

    @Override
    public ResponseEntity<DeviceList> listDevices() {
        var principal = CurrentUser.require();
        var list =
                devices.ofMember(principal.memberId()).stream()
                        .map(row -> mapper.toApi(row, principal.deviceId()))
                        .toList();
        return ResponseEntity.ok(new DeviceList(list));
    }

    @Override
    public ResponseEntity<Void> revokeDevice(UUID id) {
        // Only your own: the query filters by member ID, so someone else's device ends
        // in 404 and not 403 -- its existence is nobody else's business.
        auth.revokeDevice(CurrentUser.requireMemberId(), id);
        return ResponseEntity.noContent().build();
    }
}
