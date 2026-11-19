-- The schema of Hiwiski 2026.1.9 in one step: what migrations 1 to 36 had built, with
-- the rows they seeded -- the change sequence, the key counters, the built-in aisles
-- and the product catalog.
--
-- A new database runs this file and nothing before it. A database from 2026.1.9 or
-- 2026.1.8 is already at version 36: the server takes it over at its first start by
-- Flyway's repair (BaselineTakeover), without running anything. Every change from here
-- on is a migration of its own, V037 and up, and released migrations are never edited.
--
-- No schema is named: Flyway runs this in the schema it migrates -- `public`, or the
-- staging schema a restore builds.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE aisle (
    id uuid NOT NULL,
    key text,
    name text,
    "position" integer NOT NULL,
    hidden boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT aisle_key_or_name CHECK (((key IS NULL) <> (name IS NULL)))
);

CREATE TABLE board (
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
    kind text DEFAULT 'START'::text NOT NULL,
    name text DEFAULT ''::text NOT NULL,
    layout text DEFAULT 'FLOW'::text NOT NULL,
    columns integer DEFAULT 4 NOT NULL,
    token text
);

CREATE TABLE calendar (
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
    name text DEFAULT ''::text NOT NULL,
    color_token text DEFAULT 'BLUE'::text NOT NULL,
    kind text DEFAULT 'LOCAL'::text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    tags uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    default_reminder_minutes integer
);

CREATE TABLE calendar_feed (
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
    name text DEFAULT ''::text NOT NULL,
    calendar_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    content_mode text DEFAULT 'FULL'::text NOT NULL,
    token text NOT NULL,
    last_access_at timestamp with time zone
);

CREATE TABLE calendar_subscription (
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
    calendar_id uuid NOT NULL,
    name text DEFAULT ''::text NOT NULL,
    url text DEFAULT ''::text NOT NULL,
    target_kind text DEFAULT 'EVENT'::text NOT NULL,
    target_list_id uuid,
    sync_interval text DEFAULT 'DAILY'::text NOT NULL,
    last_sync_at timestamp with time zone,
    last_error text,
    imported_count integer DEFAULT 0 NOT NULL
);

CREATE TABLE change_log (
    seq bigint NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    container_type text,
    container_id uuid,
    op text NOT NULL,
    fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    changed_fields text[] DEFAULT '{}'::text[] NOT NULL,
    actor_member_id uuid,
    actor_device_id uuid,
    entity_version bigint NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    entity_key text
);

CREATE TABLE change_sequence (
    id boolean DEFAULT true NOT NULL,
    seq bigint DEFAULT 0 NOT NULL,
    CONSTRAINT change_sequence_single_row CHECK (id)
);

CREATE TABLE comment (
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
    item_type text NOT NULL,
    item_id uuid NOT NULL,
    body text DEFAULT ''::text NOT NULL
);

CREATE TABLE device (
    id uuid NOT NULL,
    member_id uuid NOT NULL,
    name text NOT NULL,
    platform text NOT NULL,
    token_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone,
    last_sync_seq bigint DEFAULT 0 NOT NULL,
    pending_count integer DEFAULT 0 NOT NULL,
    revoked_at timestamp with time zone,
    stay_signed_in boolean DEFAULT true NOT NULL,
    installation_id uuid
);

CREATE TABLE effective_access (
    member_id uuid NOT NULL,
    item_type text NOT NULL,
    item_id uuid NOT NULL,
    level text NOT NULL,
    source text NOT NULL,
    CONSTRAINT effective_access_level CHECK ((level = ANY (ARRAY['READ'::text, 'CHECK'::text, 'WRITE'::text]))),
    CONSTRAINT effective_access_source CHECK ((source = ANY (ARRAY['OWNER'::text, 'DIRECT'::text, 'INHERITED'::text, 'ASSIGNED'::text])))
);

CREATE TABLE entity_key_counter (
    entity_type text NOT NULL,
    next bigint DEFAULT 1 NOT NULL
);

CREATE TABLE event (
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
    calendar_id uuid NOT NULL,
    entity_key text,
    title text DEFAULT ''::text NOT NULL,
    description text,
    location text,
    time_form text DEFAULT 'TIMED'::text NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    start_date date,
    end_date date,
    local_start text,
    local_end text,
    time_zone text,
    rrule text,
    exceptions jsonb DEFAULT '{}'::jsonb NOT NULL,
    attendees uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    reminder_minutes integer,
    reminders jsonb,
    source_uid text,
    source_recurrence_id text,
    tags uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    owner_assignees uuid[] DEFAULT '{}'::uuid[] NOT NULL
);

CREATE TABLE event_publication (
    id uuid NOT NULL,
    listener_id text NOT NULL,
    event_type text NOT NULL,
    serialized_event text NOT NULL,
    publication_date timestamp with time zone NOT NULL,
    completion_date timestamp with time zone,
    status text,
    completion_attempts integer,
    last_resubmission_date timestamp with time zone
);

CREATE TABLE "group" (
    id uuid NOT NULL,
    name text NOT NULL,
    icon_token text,
    "position" integer DEFAULT 0 NOT NULL
);

CREATE TABLE group_member (
    group_id uuid NOT NULL,
    member_id uuid NOT NULL
);

CREATE TABLE instance_setting (
    key text NOT NULL,
    value text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);

CREATE TABLE invitation (
    id uuid NOT NULL,
    display_name text,
    group_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    redeemed_at timestamp with time zone,
    redeemed_member_id uuid,
    code_hash text NOT NULL
);

CREATE TABLE link (
    id uuid NOT NULL,
    from_type text NOT NULL,
    from_id uuid NOT NULL,
    to_type text NOT NULL,
    to_id uuid NOT NULL,
    label text,
    "position" integer DEFAULT 0 NOT NULL
);

CREATE TABLE list_order (
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
    list_ids jsonb DEFAULT '[]'::jsonb NOT NULL
);

CREATE TABLE media (
    id uuid NOT NULL,
    owner_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    content_type text NOT NULL,
    byte_size bigint NOT NULL,
    width integer,
    height integer,
    item_type text,
    item_id uuid,
    sha256 text
);

CREATE TABLE member (
    id uuid NOT NULL,
    username text NOT NULL,
    display_name text NOT NULL,
    password_hash text NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    color_token text DEFAULT 'SLATE'::text NOT NULL,
    theme_mode text DEFAULT 'SYSTEM'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    disabled_at timestamp with time zone,
    avatar_image_id uuid
);

CREATE TABLE processed_mutation (
    mutation_id uuid NOT NULL,
    device_id uuid,
    result text NOT NULL,
    response jsonb NOT NULL,
    processed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE product (
    id uuid NOT NULL,
    name text NOT NULL,
    default_unit text,
    usage_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    aisle_id uuid
);

CREATE TABLE search_index (
    item_type text NOT NULL,
    item_id uuid NOT NULL,
    owner_id uuid NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    entity_key text,
    context text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    document tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('german'::regconfig, COALESCE(title, ''::text)), 'A'::"char") || setweight(to_tsvector('german'::regconfig, COALESCE(body, ''::text)), 'B'::"char"))) STORED,
    archived boolean DEFAULT false NOT NULL
);

CREATE TABLE share (
    item_type text NOT NULL,
    item_id uuid NOT NULL,
    subject_type text NOT NULL,
    subject_id uuid NOT NULL,
    level text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT share_level CHECK ((level = ANY (ARRAY['READ'::text, 'CHECK'::text, 'WRITE'::text]))),
    CONSTRAINT share_subject_type CHECK ((subject_type = ANY (ARRAY['MEMBER'::text, 'GROUP'::text])))
);

CREATE TABLE tag (
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
    name text DEFAULT ''::text NOT NULL,
    color_token text DEFAULT 'BLUE'::text NOT NULL
);

CREATE TABLE todo (
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
    list_id uuid CONSTRAINT todo_list_id_not_null1 NOT NULL,
    entity_key text,
    title text DEFAULT ''::text NOT NULL,
    description text,
    status text DEFAULT 'OPEN'::text NOT NULL,
    due_date date,
    due_time time without time zone,
    rrule text,
    assignees uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    amount numeric,
    unit text,
    product_id uuid,
    tags uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    column_id uuid,
    owner_assignees uuid[] DEFAULT '{}'::uuid[] NOT NULL
);

CREATE TABLE todo_list (
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
    name text DEFAULT ''::text NOT NULL,
    kind text DEFAULT 'STANDARD'::text NOT NULL,
    color_token text DEFAULT 'BLUE'::text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    tags uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    assignees uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    description text,
    archived_at timestamp with time zone,
    archived_by uuid,
    columns jsonb,
    entity_key text,
    CONSTRAINT todo_list_kind CHECK ((kind = ANY (ARRAY['STANDARD'::text, 'SHOPPING'::text, 'KANBAN'::text])))
);

CREATE TABLE todo_occurrence (
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
    todo_id uuid NOT NULL,
    occurrence_date date NOT NULL,
    done_at timestamp with time zone,
    done_by uuid,
    skipped boolean DEFAULT false NOT NULL
);

CREATE TABLE widget (
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
    board_id uuid NOT NULL,
    kind text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    grid_x integer DEFAULT 0 NOT NULL,
    grid_y integer DEFAULT 0 NOT NULL,
    grid_w integer DEFAULT 1 NOT NULL,
    grid_h integer DEFAULT 1 NOT NULL,
    "position" integer DEFAULT 0 NOT NULL
);

CREATE TABLE wiki_page (
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
    parent_id uuid,
    "position" integer DEFAULT 0 NOT NULL,
    kind text DEFAULT 'PAGE'::text NOT NULL,
    entity_key text,
    title text DEFAULT ''::text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    tags uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE wiki_revision (
    id uuid NOT NULL,
    page_id uuid NOT NULL,
    seq integer NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    author_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    kind text DEFAULT 'SAVE'::text NOT NULL,
    change_seq bigint
);

ALTER TABLE ONLY aisle
    ADD CONSTRAINT aisle_pkey PRIMARY KEY (id);

ALTER TABLE ONLY board
    ADD CONSTRAINT board_pkey PRIMARY KEY (id);

ALTER TABLE ONLY calendar_feed
    ADD CONSTRAINT calendar_feed_pkey PRIMARY KEY (id);

ALTER TABLE ONLY calendar
    ADD CONSTRAINT calendar_pkey PRIMARY KEY (id);

ALTER TABLE ONLY calendar_subscription
    ADD CONSTRAINT calendar_subscription_pkey PRIMARY KEY (id);

ALTER TABLE ONLY change_log
    ADD CONSTRAINT change_log_pkey PRIMARY KEY (seq);

ALTER TABLE ONLY change_sequence
    ADD CONSTRAINT change_sequence_pkey PRIMARY KEY (id);

ALTER TABLE ONLY comment
    ADD CONSTRAINT comment_pkey PRIMARY KEY (id);

ALTER TABLE ONLY device
    ADD CONSTRAINT device_pkey PRIMARY KEY (id);

ALTER TABLE ONLY effective_access
    ADD CONSTRAINT effective_access_pkey PRIMARY KEY (member_id, item_type, item_id);

ALTER TABLE ONLY entity_key_counter
    ADD CONSTRAINT entity_key_counter_pkey PRIMARY KEY (entity_type);

ALTER TABLE ONLY event
    ADD CONSTRAINT event_pkey PRIMARY KEY (id);

ALTER TABLE ONLY event_publication
    ADD CONSTRAINT event_publication_pkey PRIMARY KEY (id);

ALTER TABLE ONLY group_member
    ADD CONSTRAINT group_member_pkey PRIMARY KEY (group_id, member_id);

ALTER TABLE ONLY "group"
    ADD CONSTRAINT group_pkey PRIMARY KEY (id);

ALTER TABLE ONLY instance_setting
    ADD CONSTRAINT instance_setting_pkey PRIMARY KEY (key);

ALTER TABLE ONLY invitation
    ADD CONSTRAINT invitation_pkey PRIMARY KEY (id);

ALTER TABLE ONLY link
    ADD CONSTRAINT link_pkey PRIMARY KEY (id);

ALTER TABLE ONLY list_order
    ADD CONSTRAINT list_order_pkey PRIMARY KEY (id);

ALTER TABLE ONLY media
    ADD CONSTRAINT media_pkey PRIMARY KEY (id);

ALTER TABLE ONLY member
    ADD CONSTRAINT member_pkey PRIMARY KEY (id);

ALTER TABLE ONLY processed_mutation
    ADD CONSTRAINT processed_mutation_pkey PRIMARY KEY (mutation_id);

ALTER TABLE ONLY product
    ADD CONSTRAINT product_pkey PRIMARY KEY (id);

ALTER TABLE ONLY search_index
    ADD CONSTRAINT search_index_pkey PRIMARY KEY (item_type, item_id);

ALTER TABLE ONLY share
    ADD CONSTRAINT share_pkey PRIMARY KEY (item_type, item_id, subject_type, subject_id);

ALTER TABLE ONLY tag
    ADD CONSTRAINT tag_pkey PRIMARY KEY (id);

ALTER TABLE ONLY todo_list
    ADD CONSTRAINT todo_list_pkey PRIMARY KEY (id);

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_pkey PRIMARY KEY (id);

ALTER TABLE ONLY todo
    ADD CONSTRAINT todo_pkey PRIMARY KEY (id);

ALTER TABLE ONLY widget
    ADD CONSTRAINT widget_pkey PRIMARY KEY (id);

ALTER TABLE ONLY wiki_page
    ADD CONSTRAINT wiki_page_pkey PRIMARY KEY (id);

ALTER TABLE ONLY wiki_revision
    ADD CONSTRAINT wiki_revision_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX aisle_key ON aisle USING btree (key) WHERE (key IS NOT NULL);

CREATE UNIQUE INDEX aisle_name ON aisle USING btree (lower(name)) WHERE (name IS NOT NULL);

CREATE UNIQUE INDEX board_one_per_kind ON board USING btree (owner_id, kind) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX board_token ON board USING btree (token) WHERE (token IS NOT NULL);

CREATE INDEX calendar_by_owner ON calendar USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE INDEX calendar_feed_by_owner ON calendar_feed USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX calendar_feed_token ON calendar_feed USING btree (token);

CREATE INDEX calendar_subscription_by_calendar ON calendar_subscription USING btree (calendar_id);

CREATE INDEX change_log_by_entity ON change_log USING btree (entity_type, entity_id, seq DESC);

CREATE INDEX change_log_by_recorded_at ON change_log USING btree (recorded_at);

CREATE INDEX comment_by_item ON comment USING btree (item_type, item_id) WHERE (deleted_at IS NULL);

CREATE INDEX device_by_installation ON device USING btree (installation_id) WHERE ((revoked_at IS NULL) AND (installation_id IS NOT NULL));

CREATE INDEX device_by_member ON device USING btree (member_id) WHERE (revoked_at IS NULL);

CREATE UNIQUE INDEX device_token_key ON device USING btree (token_hash);

CREATE INDEX effective_access_by_item ON effective_access USING btree (item_type, item_id);

CREATE INDEX event_by_calendar ON event USING btree (calendar_id) WHERE (deleted_at IS NULL);

CREATE INDEX event_by_owner ON event USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX event_by_source ON event USING btree (calendar_id, source_uid, source_recurrence_id) NULLS NOT DISTINCT WHERE (source_uid IS NOT NULL);

CREATE INDEX event_by_start ON event USING btree (starts_at) WHERE (deleted_at IS NULL);

CREATE INDEX event_by_start_date ON event USING btree (start_date) WHERE (deleted_at IS NULL);

CREATE INDEX event_by_tag ON event USING gin (tags);

CREATE UNIQUE INDEX event_entity_key ON event USING btree (entity_key) WHERE (entity_key IS NOT NULL);

CREATE INDEX event_publication_by_completion_date_idx ON event_publication USING btree (completion_date);

CREATE INDEX event_publication_serialized_event_hash_idx ON event_publication USING hash (serialized_event);

CREATE INDEX group_member_by_member ON group_member USING btree (member_id);

CREATE INDEX link_by_target ON link USING btree (to_type, to_id);

CREATE UNIQUE INDEX link_unique ON link USING btree (from_type, from_id, to_type, to_id);

CREATE INDEX list_order_by_owner ON list_order USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE INDEX media_by_item ON media USING btree (item_type, item_id);

CREATE INDEX media_by_owner ON media USING btree (owner_id);

CREATE INDEX media_by_sha256 ON media USING btree (sha256);

CREATE UNIQUE INDEX member_single_admin ON member USING btree ((true)) WHERE is_admin;

CREATE UNIQUE INDEX member_username_key ON member USING btree (lower(username));

CREATE INDEX processed_mutation_by_processed_at ON processed_mutation USING btree (processed_at);

CREATE INDEX product_by_aisle ON product USING btree (aisle_id);

CREATE UNIQUE INDEX product_name ON product USING btree (lower(name));

CREATE INDEX search_body_trgm ON search_index USING gin (body gin_trgm_ops);

CREATE INDEX search_by_owner ON search_index USING btree (owner_id);

CREATE INDEX search_document ON search_index USING gin (document);

CREATE UNIQUE INDEX search_entity_key ON search_index USING btree (entity_key) WHERE (entity_key IS NOT NULL);

CREATE INDEX search_title_trgm ON search_index USING gin (title gin_trgm_ops);

CREATE INDEX share_by_subject ON share USING btree (subject_type, subject_id);

CREATE INDEX tag_by_owner ON tag USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE INDEX todo_by_list ON todo USING btree (list_id) WHERE (deleted_at IS NULL);

CREATE INDEX todo_by_owner ON todo USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE INDEX todo_by_tag ON todo USING gin (tags);

CREATE UNIQUE INDEX todo_entity_key ON todo USING btree (entity_key) WHERE (entity_key IS NOT NULL);

CREATE INDEX todo_list_by_owner ON todo_list USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE INDEX todo_list_by_tag ON todo_list USING gin (tags);

CREATE UNIQUE INDEX todo_list_entity_key ON todo_list USING btree (entity_key) WHERE (entity_key IS NOT NULL);

CREATE UNIQUE INDEX todo_occurrence_by_date ON todo_occurrence USING btree (todo_id, occurrence_date);

CREATE INDEX widget_by_board ON widget USING btree (board_id) WHERE (deleted_at IS NULL);

CREATE INDEX wiki_page_by_owner ON wiki_page USING btree (owner_id) WHERE (deleted_at IS NULL);

CREATE INDEX wiki_page_by_parent ON wiki_page USING btree (parent_id) WHERE (deleted_at IS NULL);

CREATE INDEX wiki_page_by_tag ON wiki_page USING gin (tags);

CREATE UNIQUE INDEX wiki_page_entity_key ON wiki_page USING btree (entity_key) WHERE (entity_key IS NOT NULL);

CREATE INDEX wiki_revision_by_change ON wiki_revision USING btree (page_id, change_seq);

CREATE INDEX wiki_revision_by_page ON wiki_revision USING btree (page_id, created_at DESC);

CREATE UNIQUE INDEX wiki_revision_seq ON wiki_revision USING btree (page_id, seq);

ALTER TABLE ONLY board
    ADD CONSTRAINT board_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY board
    ADD CONSTRAINT board_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY board
    ADD CONSTRAINT board_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY board
    ADD CONSTRAINT board_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar
    ADD CONSTRAINT calendar_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar
    ADD CONSTRAINT calendar_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar_feed
    ADD CONSTRAINT calendar_feed_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar_feed
    ADD CONSTRAINT calendar_feed_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar_feed
    ADD CONSTRAINT calendar_feed_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY calendar_feed
    ADD CONSTRAINT calendar_feed_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar
    ADD CONSTRAINT calendar_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY calendar_subscription
    ADD CONSTRAINT calendar_subscription_calendar_id_fkey FOREIGN KEY (calendar_id) REFERENCES calendar(id) ON DELETE CASCADE;

ALTER TABLE ONLY calendar_subscription
    ADD CONSTRAINT calendar_subscription_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar_subscription
    ADD CONSTRAINT calendar_subscription_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar_subscription
    ADD CONSTRAINT calendar_subscription_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY calendar_subscription
    ADD CONSTRAINT calendar_subscription_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY calendar
    ADD CONSTRAINT calendar_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY change_log
    ADD CONSTRAINT change_log_actor_device_id_fkey FOREIGN KEY (actor_device_id) REFERENCES device(id) ON DELETE SET NULL;

ALTER TABLE ONLY change_log
    ADD CONSTRAINT change_log_actor_member_id_fkey FOREIGN KEY (actor_member_id) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY comment
    ADD CONSTRAINT comment_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY comment
    ADD CONSTRAINT comment_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY comment
    ADD CONSTRAINT comment_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY comment
    ADD CONSTRAINT comment_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY device
    ADD CONSTRAINT device_member_id_fkey FOREIGN KEY (member_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY effective_access
    ADD CONSTRAINT effective_access_member_id_fkey FOREIGN KEY (member_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_calendar_id_fkey FOREIGN KEY (calendar_id) REFERENCES calendar(id) ON DELETE CASCADE;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY event
    ADD CONSTRAINT event_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY group_member
    ADD CONSTRAINT group_member_group_id_fkey FOREIGN KEY (group_id) REFERENCES "group"(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_member
    ADD CONSTRAINT group_member_member_id_fkey FOREIGN KEY (member_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY invitation
    ADD CONSTRAINT invitation_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY invitation
    ADD CONSTRAINT invitation_redeemed_member_id_fkey FOREIGN KEY (redeemed_member_id) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY list_order
    ADD CONSTRAINT list_order_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY list_order
    ADD CONSTRAINT list_order_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY list_order
    ADD CONSTRAINT list_order_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY list_order
    ADD CONSTRAINT list_order_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY media
    ADD CONSTRAINT media_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY processed_mutation
    ADD CONSTRAINT processed_mutation_device_id_fkey FOREIGN KEY (device_id) REFERENCES device(id) ON DELETE CASCADE;

ALTER TABLE ONLY product
    ADD CONSTRAINT product_aisle_id_fkey FOREIGN KEY (aisle_id) REFERENCES aisle(id) ON DELETE SET NULL;

ALTER TABLE ONLY search_index
    ADD CONSTRAINT search_index_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY share
    ADD CONSTRAINT share_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY tag
    ADD CONSTRAINT tag_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY tag
    ADD CONSTRAINT tag_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY tag
    ADD CONSTRAINT tag_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY tag
    ADD CONSTRAINT tag_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo
    ADD CONSTRAINT todo_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo
    ADD CONSTRAINT todo_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo_list
    ADD CONSTRAINT todo_list_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo_list
    ADD CONSTRAINT todo_list_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo
    ADD CONSTRAINT todo_list_id_fkey FOREIGN KEY (list_id) REFERENCES todo_list(id) ON DELETE CASCADE;

ALTER TABLE ONLY todo_list
    ADD CONSTRAINT todo_list_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY todo_list
    ADD CONSTRAINT todo_list_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_done_by_fkey FOREIGN KEY (done_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_todo_id_fkey FOREIGN KEY (todo_id) REFERENCES todo(id) ON DELETE CASCADE;

ALTER TABLE ONLY todo_occurrence
    ADD CONSTRAINT todo_occurrence_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY todo
    ADD CONSTRAINT todo_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY todo
    ADD CONSTRAINT todo_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY widget
    ADD CONSTRAINT widget_board_id_fkey FOREIGN KEY (board_id) REFERENCES board(id) ON DELETE CASCADE;

ALTER TABLE ONLY widget
    ADD CONSTRAINT widget_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY widget
    ADD CONSTRAINT widget_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY widget
    ADD CONSTRAINT widget_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY widget
    ADD CONSTRAINT widget_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY wiki_page
    ADD CONSTRAINT wiki_page_created_by_fkey FOREIGN KEY (created_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY wiki_page
    ADD CONSTRAINT wiki_page_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY wiki_page
    ADD CONSTRAINT wiki_page_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES member(id) ON DELETE CASCADE;

ALTER TABLE ONLY wiki_page
    ADD CONSTRAINT wiki_page_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES wiki_page(id) ON DELETE CASCADE;

ALTER TABLE ONLY wiki_page
    ADD CONSTRAINT wiki_page_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY wiki_revision
    ADD CONSTRAINT wiki_revision_author_id_fkey FOREIGN KEY (author_id) REFERENCES member(id) ON DELETE SET NULL;

ALTER TABLE ONLY wiki_revision
    ADD CONSTRAINT wiki_revision_page_id_fkey FOREIGN KEY (page_id) REFERENCES wiki_page(id) ON DELETE CASCADE;

-- The seeded rows.

INSERT INTO aisle (id, key, name, "position", hidden, created_at) VALUES
	('cf3bc0b6-bfb9-4663-952f-79aee97434d6', 'produce', NULL, 0, false, '2026-11-06 12:12:48.278681+00'),
	('510cc410-cb7b-4b53-92f8-700cf2160565', 'bakery', NULL, 1, false, '2026-11-06 12:12:48.278681+00'),
	('8dfd9a69-dae5-49c4-a32a-636e36fff0bc', 'meat_seafood', NULL, 2, false, '2026-11-06 12:12:48.278681+00'),
	('121e7d89-bbdc-4cbb-b33f-d2e63edacdbb', 'deli', NULL, 3, false, '2026-11-06 12:12:48.278681+00'),
	('cb2de183-0841-4c80-ba73-3ea7a4cc78a2', 'dairy_eggs', NULL, 4, false, '2026-11-06 12:12:48.278681+00'),
	('6d0326ad-e2e5-4aed-9a93-17bc8139e291', 'breakfast', NULL, 5, false, '2026-11-06 12:12:48.278681+00'),
	('5061f51b-5ac1-4d2d-a294-87e0b1c0f542', 'pantry', NULL, 6, false, '2026-11-06 12:12:48.278681+00'),
	('1e9ce525-bdad-472a-aad4-03435d15197a', 'spices_condiments', NULL, 7, false, '2026-11-06 12:12:48.278681+00'),
	('1ba51c8b-5305-4616-b5cb-f2ee1795015f', 'snacks_sweets', NULL, 8, false, '2026-11-06 12:12:48.278681+00'),
	('2f42dca2-5d11-4da9-99d2-c36882374b8f', 'beverages', NULL, 9, false, '2026-11-06 12:12:48.278681+00'),
	('eb0fdd18-18de-40ff-888c-daaa5c1d4f29', 'frozen', NULL, 10, false, '2026-11-06 12:12:48.278681+00'),
	('bb61455e-e769-4e2f-a74c-25eb6a9e48e5', 'baby', NULL, 11, false, '2026-11-06 12:12:48.278681+00'),
	('2dc1c409-70f5-478e-bb86-04b99398d589', 'personal_care', NULL, 12, false, '2026-11-06 12:12:48.278681+00'),
	('a79440b8-8400-46a7-9f83-f8d72fc25c7f', 'household', NULL, 13, false, '2026-11-06 12:12:48.278681+00'),
	('4ad0040e-1429-4524-82ef-aa1132a841c8', 'pet', NULL, 14, false, '2026-11-06 12:12:48.278681+00');

INSERT INTO change_sequence (id, seq) VALUES
	(true, 0);

INSERT INTO entity_key_counter (entity_type, next) VALUES
	('TODO', 1),
	('EVENT', 1),
	('WIKI_PAGE', 1),
	('RECIPE', 1),
	('TODO_LIST', 1);

INSERT INTO product (id, name, default_unit, usage_count, created_at, aisle_id) VALUES
	('22097b04-1a93-4962-a547-6fa8550d9822', 'Äpfel', 'kg', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('966f8154-332e-44e6-ab44-a53a2ab2422f', 'Bananen', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('cf861f39-cb15-4260-9c35-0a56389305bc', 'Birnen', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('3406b3bf-de3e-41ef-aaa4-6d728409a0a4', 'Zitronen', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('4eab2229-e0e3-450c-83b8-81396286d2a3', 'Orangen', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('e4330e10-bcdc-4a34-a483-7fbbcf38a40c', 'Trauben', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('daf84acf-ec52-4b6b-8dd1-c34aa5900a6a', 'Beeren', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('d728b1c6-6eda-401a-a5d7-4108fc097397', 'Tomaten', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('fe329654-0508-4e4c-95a6-328a84c7a267', 'Gurke', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('dad9b62d-28e6-4f7f-b75d-656309bf9f5f', 'Paprika', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('59cb1740-d6f8-455d-ab80-6c6abc818cd7', 'Zwiebel', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('5c4725db-e09f-48ea-afe0-af72e49acd8a', 'Knoblauch', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('c34ca646-c3f0-477e-a1c9-ecf4f65cb165', 'Ingwer', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('a847d4cb-eee9-4688-affa-bd003e5905c5', 'Kartoffeln', 'kg', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('0f2b6fc1-3c29-47b7-8e23-62954b49a139', 'Möhren', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('b8aa5ec3-0d04-4c35-8e56-49a21b3e3df1', 'Karotten', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('0c450f16-54bf-4058-97aa-bcb47893adb7', 'Salat', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('71e2fc63-f36f-4a52-8c44-e436a8d559b6', 'Brokkoli', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('9bf7f1a3-f8a4-4680-b4cc-38fdfa44d045', 'Zucchini', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('38c8a38d-258f-45c4-9e6a-b2c8dd5c7275', 'Pilze', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('04fcdab8-ec3c-48c3-8677-61ac1ef43e39', 'Champignons', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('32ddb68e-278c-4a3a-a3b3-acf24062c214', 'Hokkaido-Kürbis', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('a0c302d8-ef20-4b4e-9342-4e4d3c9a42f5', 'Kürbis', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('2e98f632-628a-4028-9f49-0c2869852822', 'Petersilie', 'Bund', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('53c372da-1c00-499d-8c67-569940336f4e', 'Schnittlauch', 'Bund', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('f504f366-676c-4165-858b-5f7b1bb2740f', 'Basilikum', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('bd2d9cfa-a40f-47f4-b1f9-c3c4d4998898', 'Avocado', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('3178a5b1-2933-4495-b1de-ce4708a88b01', 'Lauch', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('93bc314c-a5b7-4f99-ae9a-23077a7d99c1', 'Spinat', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cf3bc0b6-bfb9-4663-952f-79aee97434d6'),
	('fce64651-da62-46f6-9be1-a53a3b3c2530', 'Milch', 'l', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('100be81b-14b4-4e24-a732-78ba160bbab1', 'Hafermilch', 'l', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('14252d27-bc68-4c47-bac7-6c74bb5dfca3', 'Butter', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('f4c2e4e3-9a12-494e-a337-2171b8fbf31a', 'Quark', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('1b892843-8d7d-4a4b-9aba-d846e1beaad1', 'Joghurt', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('c2abb3dd-2452-46e3-b509-f5ce47ff5ef2', 'Sahne', 'ml', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('6a64faaa-42e1-413f-a269-78b69a9cb556', 'Schmand', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('706b99a6-ea79-4017-bc25-3610cc2f55b3', 'Käse', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('8a5b54fb-cf79-4002-bf68-1888eeebdad2', 'Feta', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('65e4cb86-cf83-48cc-b839-1e20bd8c4dbb', 'Mozzarella', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('5da48233-ec1d-4d31-8e49-9a5c0a4339a6', 'Parmesan', 'g', 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('6507b041-7405-4ae2-9d81-f2ee52b41605', 'Eier', NULL, 0, '2026-11-06 12:12:47.890557+00', 'cb2de183-0841-4c80-ba73-3ea7a4cc78a2'),
	('3f9d2773-d87f-4907-8367-c5344cffbd5c', 'Schinken', 'g', 0, '2026-11-06 12:12:47.890557+00', '121e7d89-bbdc-4cbb-b33f-d2e63edacdbb'),
	('79b7f4a4-8019-4169-8ba8-48a3ee84d928', 'Wurst', 'g', 0, '2026-11-06 12:12:47.890557+00', '121e7d89-bbdc-4cbb-b33f-d2e63edacdbb'),
	('b7c3ba16-e61c-4b2a-878c-3db6b5566828', 'Tofu', 'g', 0, '2026-11-06 12:12:47.890557+00', '121e7d89-bbdc-4cbb-b33f-d2e63edacdbb'),
	('43778218-7f15-4a0f-b024-8bcd831448b8', 'Hackfleisch', 'g', 0, '2026-11-06 12:12:47.890557+00', '8dfd9a69-dae5-49c4-a32a-636e36fff0bc'),
	('360df28b-9615-49fb-a60e-9ffc7cdc27a2', 'Hähnchen', 'g', 0, '2026-11-06 12:12:47.890557+00', '8dfd9a69-dae5-49c4-a32a-636e36fff0bc'),
	('f93f9aae-ea0f-4ed8-ac27-4ad6c9cbef4a', 'Rinderrouladen', NULL, 0, '2026-11-06 12:12:47.890557+00', '8dfd9a69-dae5-49c4-a32a-636e36fff0bc'),
	('b4fb1acc-654d-4c22-a9f6-dacfe6ab05d2', 'Lachs', 'g', 0, '2026-11-06 12:12:47.890557+00', '8dfd9a69-dae5-49c4-a32a-636e36fff0bc'),
	('4f1c2aa2-2810-4c28-8450-a99b5fca4988', 'Brot', NULL, 0, '2026-11-06 12:12:47.890557+00', '510cc410-cb7b-4b53-92f8-700cf2160565'),
	('26974ada-6b51-4116-8a7d-f96c0480c795', 'Vollkornbrot', NULL, 0, '2026-11-06 12:12:47.890557+00', '510cc410-cb7b-4b53-92f8-700cf2160565'),
	('d15d5dd4-f4ea-4488-b676-dc1f0db2d8d4', 'Brötchen', NULL, 0, '2026-11-06 12:12:47.890557+00', '510cc410-cb7b-4b53-92f8-700cf2160565'),
	('f7b22f31-7e92-4567-9c13-08834f4dbcbd', 'Toast', NULL, 0, '2026-11-06 12:12:47.890557+00', '510cc410-cb7b-4b53-92f8-700cf2160565'),
	('048df78c-1f16-4a02-b1fc-da44651559cb', 'Mehl', 'kg', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('37fba40d-fcc7-4253-b9a7-20bf0d9656e6', 'Zucker', 'kg', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('733174fe-bb57-4e9e-9cb5-d7e624f5fb47', 'Salz', NULL, 0, '2026-11-06 12:12:47.890557+00', '1e9ce525-bdad-472a-aad4-03435d15197a'),
	('3cba3d55-a263-4551-85ad-039a0c8ae13e', 'Pfeffer', NULL, 0, '2026-11-06 12:12:47.890557+00', '1e9ce525-bdad-472a-aad4-03435d15197a'),
	('a8597229-3f02-4f04-9864-1d38380e7876', 'Reis', 'g', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('5004e001-47b7-46e2-aa93-58f6a74a3d27', 'Nudeln', 'g', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('36e3e655-db7a-4f69-a9d8-12d3a82ed41b', 'Spaghetti', 'g', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('5a9d1504-6422-48f3-bd49-25c23b0b6bb1', 'Linsen', 'g', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('86d99787-64cf-441a-852e-460e840b3750', 'Haferflocken', 'g', 0, '2026-11-06 12:12:47.890557+00', '6d0326ad-e2e5-4aed-9a93-17bc8139e291'),
	('3828c4bd-c54e-4e8b-898f-6790aa974089', 'Müsli', 'g', 0, '2026-11-06 12:12:47.890557+00', '6d0326ad-e2e5-4aed-9a93-17bc8139e291'),
	('68b1fb15-1a48-40f3-8f8d-a366a27dd43b', 'Öl', 'ml', 0, '2026-11-06 12:12:47.890557+00', '1e9ce525-bdad-472a-aad4-03435d15197a'),
	('c28acb76-3fef-418c-95f1-201f0e52bddb', 'Olivenöl', 'ml', 0, '2026-11-06 12:12:47.890557+00', '1e9ce525-bdad-472a-aad4-03435d15197a'),
	('389c68d0-bfa0-484a-8b19-27d6a9986b6f', 'Essig', 'ml', 0, '2026-11-06 12:12:47.890557+00', '1e9ce525-bdad-472a-aad4-03435d15197a'),
	('fae3ec11-077d-4fec-a90e-fd2e735f2a5d', 'Gemüsebrühe', 'ml', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('ad291903-93b1-4341-bb65-0e5b5bbd39b5', 'Kokosmilch', 'ml', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('85925c7c-ea91-4910-b64a-b99eb6369083', 'Passierte Tomaten', 'g', 0, '2026-11-06 12:12:47.890557+00', '5061f51b-5ac1-4d2d-a294-87e0b1c0f542'),
	('21cc7ed3-b43f-4e24-9125-df0f17a9b30e', 'Honig', NULL, 0, '2026-11-06 12:12:47.890557+00', '6d0326ad-e2e5-4aed-9a93-17bc8139e291'),
	('008961ee-a12f-46c0-ad73-3133fc4bedb2', 'Marmelade', NULL, 0, '2026-11-06 12:12:47.890557+00', '6d0326ad-e2e5-4aed-9a93-17bc8139e291'),
	('0d6f7155-138a-4e32-bf8b-cb1d3d2e1c8c', 'Kaffee', 'g', 0, '2026-11-06 12:12:47.890557+00', '6d0326ad-e2e5-4aed-9a93-17bc8139e291'),
	('c92dd34a-40b7-42e5-b946-8d5b6df7aac7', 'Tee', NULL, 0, '2026-11-06 12:12:47.890557+00', '6d0326ad-e2e5-4aed-9a93-17bc8139e291'),
	('49940d12-9cd4-4eb8-9bf1-845c68257138', 'Schokolade', NULL, 0, '2026-11-06 12:12:47.890557+00', '1ba51c8b-5305-4616-b5cb-f2ee1795015f'),
	('d14331b8-4fe6-4451-88a4-91012ed6a557', 'Kekse', NULL, 0, '2026-11-06 12:12:47.890557+00', '1ba51c8b-5305-4616-b5cb-f2ee1795015f'),
	('7562a3f6-b2a4-4112-9fed-614428d3e369', 'Chips', NULL, 0, '2026-11-06 12:12:47.890557+00', '1ba51c8b-5305-4616-b5cb-f2ee1795015f'),
	('e2262877-0a7d-4944-8cbf-cc61e47c7c5a', 'Wasser', 'l', 0, '2026-11-06 12:12:47.890557+00', '2f42dca2-5d11-4da9-99d2-c36882374b8f'),
	('fddce39c-58fb-4ed4-8b35-d71257ebe691', 'Saft', 'l', 0, '2026-11-06 12:12:47.890557+00', '2f42dca2-5d11-4da9-99d2-c36882374b8f'),
	('8b20e91e-96aa-4d9b-8fbd-7ccdb68f2d68', 'Apfelsaft', 'l', 0, '2026-11-06 12:12:47.890557+00', '2f42dca2-5d11-4da9-99d2-c36882374b8f'),
	('ae045c62-72ad-45cf-90a5-54fbd651cef9', 'Bier', NULL, 0, '2026-11-06 12:12:47.890557+00', '2f42dca2-5d11-4da9-99d2-c36882374b8f'),
	('c9f3b7d3-7205-477a-877f-dde9d37227f6', 'Wein', NULL, 0, '2026-11-06 12:12:47.890557+00', '2f42dca2-5d11-4da9-99d2-c36882374b8f'),
	('366e4a86-49c3-45a9-b88d-075eb428ab78', 'Tiefkühlerbsen', 'g', 0, '2026-11-06 12:12:47.890557+00', 'eb0fdd18-18de-40ff-888c-daaa5c1d4f29'),
	('eb1b86ad-4d3b-4b1d-904a-cdf561c4a8f3', 'Pizza', NULL, 0, '2026-11-06 12:12:47.890557+00', 'eb0fdd18-18de-40ff-888c-daaa5c1d4f29'),
	('b5c026d6-98b0-42c0-a17f-84f06da74a0c', 'Eis', NULL, 0, '2026-11-06 12:12:47.890557+00', 'eb0fdd18-18de-40ff-888c-daaa5c1d4f29'),
	('bbdb4ffb-cf5e-4900-88ab-7f444a26d79c', 'Spülmittel', NULL, 0, '2026-11-06 12:12:47.890557+00', 'a79440b8-8400-46a7-9f83-f8d72fc25c7f'),
	('56b66b4b-ed0b-41a3-acd9-2bcd9458b364', 'Waschmittel', NULL, 0, '2026-11-06 12:12:47.890557+00', 'a79440b8-8400-46a7-9f83-f8d72fc25c7f'),
	('540a8afa-3ea0-4dd6-a32d-7d6b2adae082', 'Toilettenpapier', NULL, 0, '2026-11-06 12:12:47.890557+00', 'a79440b8-8400-46a7-9f83-f8d72fc25c7f'),
	('50e3281c-e1f2-4f86-88c6-11dad8b31a08', 'Küchenrolle', NULL, 0, '2026-11-06 12:12:47.890557+00', 'a79440b8-8400-46a7-9f83-f8d72fc25c7f'),
	('5223c637-5425-4ed8-a6f1-346a98738f33', 'Zahnpasta', NULL, 0, '2026-11-06 12:12:47.890557+00', '2dc1c409-70f5-478e-bb86-04b99398d589'),
	('8d936797-63d7-432d-80a6-7987fc980b88', 'Shampoo', NULL, 0, '2026-11-06 12:12:47.890557+00', '2dc1c409-70f5-478e-bb86-04b99398d589'),
	('de09c917-5fbc-4593-b41b-19a90390df26', 'Duschgel', NULL, 0, '2026-11-06 12:12:47.890557+00', '2dc1c409-70f5-478e-bb86-04b99398d589'),
	('beb6a6ed-7295-41a4-ba82-463bc930a343', 'Müllbeutel', NULL, 0, '2026-11-06 12:12:47.890557+00', 'a79440b8-8400-46a7-9f83-f8d72fc25c7f');
