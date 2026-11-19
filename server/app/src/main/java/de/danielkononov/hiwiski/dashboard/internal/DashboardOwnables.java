package de.danielkononov.hiwiski.dashboard.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.BOARD;
import static de.danielkononov.hiwiski.db.generated.Tables.WIDGET;

import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.admin.JooqTokenCarryOver;
import de.danielkononov.hiwiski.admin.RestoreCarryOver;
import org.jooq.DSLContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code dashboard} registers with {@code access} and {@code admin}.
 *
 * <p>A board belongs to exactly one member and is not shared: "Only your own start
 * board is changed". The <em>contents</em> of the tiles are subject to
 * the share of their source — a calendar widget shows only what its owner may see.
 *
 * <p>No {@code Restorable}: a board that is always there and creates itself on first
 * opening needs no trash.
 */
@Configuration
class DashboardOwnables {

    @Bean
    Ownable boardOwnable(DSLContext db) {
        return new JooqOwnable(db, DashboardSyncTypes.BOARD_TYPE, BOARD) {

            @Override
            public boolean shareable() {
                return false;
            }
        };
    }

    @Bean
    Ownable widgetOwnable(DSLContext db) {
        return new JooqOwnable(
                db,
                DashboardSyncTypes.WIDGET_TYPE,
                WIDGET,
                DashboardSyncTypes.BOARD_TYPE,
                WIDGET.BOARD_ID) {

            @Override
            public boolean shareable() {
                return false;
            }
        };
    }

    /**
     * A board's address survives a restore as it is now: one replaced after a leak must
     * not come back with an older archive.
     */
    @Bean
    RestoreCarryOver boardTokens(DSLContext db) {
        return new JooqTokenCarryOver(db, BOARD, BOARD.ID, BOARD.TOKEN);
    }
}
