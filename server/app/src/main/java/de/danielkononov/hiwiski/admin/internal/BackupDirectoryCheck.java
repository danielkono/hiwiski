package de.danielkononov.hiwiski.admin.internal;

import java.nio.file.Path;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

/**
 * <strong>The server checks at start that it can write into the backup directory</strong>
 * and does not start otherwise. A share mounted
 * read-only or owned by someone else would otherwise fail at two in the night, unseen.
 */
@Component
class BackupDirectoryCheck {

    BackupDirectoryCheck(@Value("${hiwiski.backup-path}") String backupPath, ObjectMapper json) {
        new BackupDirectory(Path.of(backupPath), json).requireWritable();
    }
}
