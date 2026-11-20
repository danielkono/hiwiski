package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.api.SetupRestoreApi;
import de.danielkononov.hiwiski.api.model.BackupPasswordEntry;
import de.danielkononov.hiwiski.api.model.BackupPreview;
import de.danielkononov.hiwiski.api.model.RestoreResult;
import de.danielkononov.hiwiski.identity.SetupGate;
import java.io.IOException;
import java.nio.file.Files;
import org.jspecify.annotations.Nullable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * Restoring on a fresh server, from the setup wizard -- for a new machine after the old
 * one is gone.
 *
 * <p>No sign-in, there is no one yet; the setup code instead, on every call where the
 * operator switched it on, and an instance nobody has set up.
 */
@RestController
class SetupRestoreController implements SetupRestoreApi {

    private final BackupService backups;
    private final SetupGate setup;

    SetupRestoreController(BackupService backups, SetupGate setup) {
        this.backups = backups;
        this.setup = setup;
    }

    @Override
    public ResponseEntity<BackupPreview> inspectSetupBackup(
            String id, BackupPasswordEntry entry, @Nullable String setupCode) {
        setup.requireCode(setupCode, setup.currentClient());
        setup.requireFresh();
        return ResponseEntity.ok(AdminController.toApi(backups.inspect(backups.uploaded(id), entry.getPassword())));
    }

    @Override
    public ResponseEntity<RestoreResult> restoreSetupBackup(
            String id, BackupPasswordEntry entry, @Nullable String setupCode) throws IOException {
        setup.requireCode(setupCode, setup.currentClient());
        var file = backups.uploaded(id);
        var outcome = backups.restoreOnFreshInstance(file, entry.getPassword());
        Files.deleteIfExists(file);
        return ResponseEntity.ok(new RestoreResult(outcome.instanceId(), (int) outcome.rows()));
    }
}
