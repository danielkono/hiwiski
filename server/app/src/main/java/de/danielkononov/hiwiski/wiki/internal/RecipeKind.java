package de.danielkononov.hiwiski.wiki.internal;

import de.danielkononov.hiwiski.platform.KeyedEntityType;
import de.danielkononov.hiwiski.sync.SyncProperty;
import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Component;

/** A recipe: servings, the ingredients, where it comes from, its picture and time. */
@Component
class RecipeKind implements WikiKind {

    static final String CODE = "RECIPE";
    static final String IMAGE_ID = "imageId";

    @Override
    public String code() {
        return CODE;
    }

    @Override
    public List<SyncProperty> properties() {
        return List.of(
                SyncProperty.integer("servings"),
                // The ingredients go as a whole: an ingredient list is an ordered
                // sequence, and two devices changing line 3 at the same time mean the
                // same field. Merging here would yield a list nobody wrote.
                SyncProperty.json("ingredients"),
                SyncProperty.text("sourceUrl"),
                SyncProperty.uuid(IMAGE_ID),
                SyncProperty.integer("durationMinutes"));
    }

    @Override
    public Optional<KeyedEntityType> keyType() {
        return Optional.of(KeyedEntityType.RECIPE);
    }

    @Override
    public List<String> imageProperties() {
        return List.of(IMAGE_ID);
    }
}
