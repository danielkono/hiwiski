-- A mind map is a wiki page of the kind MINDMAP. Its elements and the connections
-- between them are items of their own, each with the standard columns of a synced
-- table, so that two people changing different elements of the same map never collide
-- and a conflict names the one element (and field) both of them changed. Kept in a
-- property of the page, the whole map would be one field and every concurrent change a
-- conflict about all of it.
--
-- Only new tables: the previous server version starts on this schema unchanged.

CREATE TABLE mindmap_node (
    id uuid NOT NULL,
    owner_id uuid NOT NULL,
    version bigint NOT NULL,
    field_seq jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    page_id uuid NOT NULL,
    kind text DEFAULT 'PLAIN'::text NOT NULL,
    x integer DEFAULT 0 NOT NULL,
    y integer DEFAULT 0 NOT NULL,
    width integer DEFAULT 160 NOT NULL,
    height integer DEFAULT 80 NOT NULL,
    -- The stacking order. A fraction, so that moving an element one step up or down
    -- writes that element alone: it goes halfway between its new neighbours.
    layer numeric DEFAULT 0 NOT NULL,
    -- Plain text, a note's Markdown, or a picture element's picture as a Markdown
    -- image, the way a page's text holds one.
    text text DEFAULT ''::text NOT NULL,
    target text,
    -- What a link element shows of its target: TITLE, or CONTENT as its preview does.
    link_view text,
    -- An accent token (BLUE, RUST, ...) or a colour of the family's own choice as
    -- #RRGGBB; the app adapts the latter to the light and the dark theme.
    color text,
    -- The outline of an element with a surface (ROUNDED, RECTANGLE, ELLIPSE, PILL,
    -- DIAMOND); of a stroke, the shape it was drawn as (RECTANGLE, ELLIPSE, TRIANGLE,
    -- DIAMOND, LINE, ARROW), which may be resized — empty: drawn freehand. Names in
    -- capitals: an app draws one it does not know as the plain one.
    shape text,
    -- S, M, L or XL — or a size of its own, in logical pixels ("18").
    text_size text,
    -- The colour of its text, the same way as `color`; empty: the theme's own.
    text_color text,
    -- A stroke drawn by hand: its points across the element, each as two whole
    -- numbers from 0 to 10000 ("x,y x,y ..."), so it scales with the element; and how
    -- thick it is drawn. Each stroke an element of its own: two people drawing at
    -- once never collide, and one is erased, moved or taken back alone.
    points text,
    stroke_width integer,
    -- Turned clockwise about its centre, in whole degrees from 0 to 359; empty: not
    -- turned.
    rotation integer,
    -- Where its text stands inside it: TOP_LEFT, TOP_CENTER, TOP_RIGHT, MIDDLE_LEFT,
    -- CENTER, MIDDLE_RIGHT, BOTTOM_LEFT, BOTTOM_CENTER or BOTTOM_RIGHT; empty: top left.
    text_align text,
    -- What its lines fill: BOX, the largest box inside its shape, or SHAPE, the shape
    -- itself; empty: BOX.
    text_flow text
);

CREATE TABLE mindmap_edge (
    id uuid NOT NULL,
    owner_id uuid NOT NULL,
    version bigint NOT NULL,
    field_seq jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    page_id uuid NOT NULL,
    from_id uuid NOT NULL,
    to_id uuid NOT NULL,
    text text DEFAULT ''::text NOT NULL,
    color text,
    -- How thick the line is drawn; empty: the app's own.
    stroke_width integer,
    -- SOLID, DASHED or DOTTED; empty: solid.
    line text,
    -- Arrow heads: END at the element it goes to, START at the one it comes from,
    -- BOTH, or NONE; empty: none.
    arrows text
);

ALTER TABLE ONLY mindmap_node
    ADD CONSTRAINT mindmap_node_pkey PRIMARY KEY (id);

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_pkey PRIMARY KEY (id);

-- Over deleted rows too, unlike the other tables' indexes: a page brought back from
-- the trash looks for what was deleted with it, removing a page or an element for good
-- removes its elements and connections through the keys below, and a page's share
-- reaches every element it holds. A map has hundreds of them; without these, each of
-- those read the whole table.
CREATE INDEX mindmap_node_by_page ON mindmap_node USING btree (page_id);

CREATE INDEX mindmap_edge_by_page ON mindmap_edge USING btree (page_id);

CREATE INDEX mindmap_edge_by_from ON mindmap_edge USING btree (from_id);

CREATE INDEX mindmap_edge_by_to ON mindmap_edge USING btree (to_id);

-- Gone for good with their page: the trash removes a page after its retention period.
ALTER TABLE ONLY mindmap_node
    ADD CONSTRAINT mindmap_node_page_id_fkey FOREIGN KEY (page_id) REFERENCES wiki_page(id) ON DELETE CASCADE;

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_page_id_fkey FOREIGN KEY (page_id) REFERENCES wiki_page(id) ON DELETE CASCADE;

-- And a connection with either of its elements. The server checks both ends before it
-- writes a connection, so the keys never refuse a push.
ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_from_id_fkey FOREIGN KEY (from_id) REFERENCES mindmap_node(id) ON DELETE CASCADE;

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_to_id_fkey FOREIGN KEY (to_id) REFERENCES mindmap_node(id) ON DELETE CASCADE;

ALTER TABLE ONLY mindmap_node
    ADD CONSTRAINT mindmap_node_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY mindmap_node
    ADD CONSTRAINT mindmap_node_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY mindmap_node
    ADD CONSTRAINT mindmap_node_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY mindmap_node
    ADD CONSTRAINT mindmap_node_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY mindmap_edge
    ADD CONSTRAINT mindmap_edge_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;
