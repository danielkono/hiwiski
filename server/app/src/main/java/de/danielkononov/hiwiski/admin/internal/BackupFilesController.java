package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.api.BackupFilesApi;
import de.danielkononov.hiwiski.api.model.BackupUpload;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.identity.SetupGate;
import java.io.IOException;
import java.io.InputStream;
import org.jspecify.annotations.Nullable;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * Archives in and out -- streamed both ways,
 * past the limit for images.
 */
@RestController
class BackupFilesController implements BackupFilesApi {

    private final BackupService backups;
    private final SetupGate setup;

    BackupFilesController(BackupService backups, SetupGate setup) {
        this.backups = backups;
        this.setup = setup;
    }

    @Override
    public ResponseEntity<Resource> downloadBackup(String id) {
        CurrentUser.require().requireAdmin();
        var archive = backups.archive(id);
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .contentLength(archive.bytes())
                .header(
                        HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment()
                                .filename("hiwiski-" + archive.id() + BackupDirectory.SUFFIX)
                                .build()
                                .toString())
                .body(new FileSystemResource(archive.file()));
    }

    @Override
    public ResponseEntity<BackupUpload> uploadBackup(Resource body) throws IOException {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.status(HttpStatus.CREATED).body(store(body));
    }

    @Override
    public ResponseEntity<BackupUpload> uploadSetupBackup(Resource body, @Nullable String setupCode) throws IOException {
        // The code before anything is read, the fresh instance before anything is stored.
        setup.requireCode(setupCode, setup.currentClient());
        setup.requireFresh();
        return ResponseEntity.status(HttpStatus.CREATED).body(store(body));
    }

    private BackupUpload store(Resource body) throws IOException {
        try (InputStream in = body.getInputStream()) {
            var upload = backups.upload(in);
            return new BackupUpload(upload.id(), upload.bytes());
        }
    }
}
