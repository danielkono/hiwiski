package de.danielkononov.hiwiski.catalog.internal;

import de.danielkononov.hiwiski.api.CatalogApi;
import de.danielkononov.hiwiski.api.model.Aisle;
import de.danielkononov.hiwiski.api.model.AisleList;
import de.danielkononov.hiwiski.api.model.AisleOrderRequest;
import de.danielkononov.hiwiski.api.model.AssignProductAisleRequest;
import de.danielkononov.hiwiski.api.model.CreateAisleRequest;
import de.danielkononov.hiwiski.api.model.Product;
import de.danielkononov.hiwiski.api.model.ProductList;
import de.danielkononov.hiwiski.api.model.UpdateAisleRequest;
import de.danielkononov.hiwiski.identity.CurrentUser;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * The product catalog and the shopping list's categories.
 *
 * <p>It <strong>grows from input and belongs to everyone</strong> — the only domain
 * entity without an owner and without a share. Without a shared
 * entry there would be no way to tell that two recipes mean the same thing, and the
 * shopping list would not know which category "Quark" belongs in.
 *
 * <p>Hence no sync either: there is nothing to share and nothing to own. Every signed-in
 * member may change it — the family's catalog is the family's.
 */
@RestController
class CatalogController implements CatalogApi {

    private final CatalogService catalog;

    CatalogController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @Override
    public ResponseEntity<ProductList> listProducts(String query) {
        CurrentUser.require();
        return ResponseEntity.ok(new ProductList(catalog.products(query)));
    }

    @Override
    public ResponseEntity<Product> assignProductAisle(AssignProductAisleRequest request) {
        CurrentUser.require();
        return ResponseEntity.ok(catalog.assign(request.getName(), request.getAisleId()));
    }

    @Override
    public ResponseEntity<AisleList> listAisles() {
        CurrentUser.require();
        return ResponseEntity.ok(new AisleList(catalog.aisles()));
    }

    @Override
    public ResponseEntity<Aisle> createAisle(CreateAisleRequest request) {
        CurrentUser.require();
        return ResponseEntity.status(HttpStatus.CREATED).body(catalog.createAisle(request.getName()));
    }

    @Override
    public ResponseEntity<Aisle> updateAisle(UUID id, UpdateAisleRequest request) {
        CurrentUser.require();
        return ResponseEntity.ok(catalog.updateAisle(id, request.getName(), request.getHidden()));
    }

    @Override
    public ResponseEntity<Void> deleteAisle(UUID id) {
        CurrentUser.require();
        catalog.deleteAisle(id);
        return ResponseEntity.noContent().build();
    }

    @Override
    public ResponseEntity<AisleList> reorderAisles(AisleOrderRequest request) {
        CurrentUser.require();
        return ResponseEntity.ok(new AisleList(catalog.reorder(request.getIds())));
    }
}
