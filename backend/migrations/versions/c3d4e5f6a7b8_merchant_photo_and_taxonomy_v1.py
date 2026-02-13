"""merchant photo and taxonomy v1

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f602
Create Date: 2026-02-13 20:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "c3d4e5f6a7b8"
down_revision = "b2c3d4e5f602"
branch_labels = None
depends_on = None


def _table_exists(bind, table_name: str) -> bool:
    try:
        return sa.inspect(bind).has_table(table_name)
    except Exception:
        return False


def _column_exists(bind, table_name: str, column_name: str) -> bool:
    try:
        cols = sa.inspect(bind).get_columns(table_name)
        return any((c.get("name") or "") == column_name for c in cols)
    except Exception:
        return False


def _index_exists(bind, table_name: str, index_name: str) -> bool:
    try:
        rows = sa.inspect(bind).get_indexes(table_name)
        return any((r.get("name") or "") == index_name for r in rows)
    except Exception:
        return False


def _add_user_profile_photo_column(bind):
    if not _table_exists(bind, "users"):
        return
    if _column_exists(bind, "users", "profile_image_url"):
        return
    with op.batch_alter_table("users") as batch:
        batch.add_column(sa.Column("profile_image_url", sa.String(length=1024), nullable=True))


def _create_taxonomy_tables(bind):
    if not _table_exists(bind, "categories"):
        op.create_table(
            "categories",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("slug", sa.String(length=140), nullable=False),
            sa.Column("parent_id", sa.Integer(), nullable=True),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("slug", name="uq_categories_slug"),
        )
        op.create_index("ix_categories_slug", "categories", ["slug"], unique=False)
        op.create_index("ix_categories_parent_id", "categories", ["parent_id"], unique=False)
    if not _table_exists(bind, "brands"):
        op.create_table(
            "brands",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("slug", sa.String(length=140), nullable=False),
            sa.Column("category_id", sa.Integer(), nullable=True),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("slug", name="uq_brands_slug"),
        )
        op.create_index("ix_brands_slug", "brands", ["slug"], unique=False)
        op.create_index("ix_brands_category_id", "brands", ["category_id"], unique=False)
    if not _table_exists(bind, "brand_models"):
        op.create_table(
            "brand_models",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("slug", sa.String(length=140), nullable=False),
            sa.Column("brand_id", sa.Integer(), nullable=True),
            sa.Column("category_id", sa.Integer(), nullable=True),
            sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.UniqueConstraint("slug", name="uq_brand_models_slug"),
        )
        op.create_index("ix_brand_models_slug", "brand_models", ["slug"], unique=False)
        op.create_index("ix_brand_models_brand_id", "brand_models", ["brand_id"], unique=False)
        op.create_index("ix_brand_models_category_id", "brand_models", ["category_id"], unique=False)


def _add_listing_taxonomy_columns(bind):
    if not _table_exists(bind, "listings"):
        return
    add = []
    if not _column_exists(bind, "listings", "category_id"):
        add.append(sa.Column("category_id", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "brand_id"):
        add.append(sa.Column("brand_id", sa.Integer(), nullable=True))
    if not _column_exists(bind, "listings", "model_id"):
        add.append(sa.Column("model_id", sa.Integer(), nullable=True))
    if add:
        with op.batch_alter_table("listings") as batch:
            for col in add:
                batch.add_column(col)
    if not _index_exists(bind, "listings", "ix_listings_category_id"):
        with op.batch_alter_table("listings") as batch:
            batch.create_index("ix_listings_category_id", ["category_id"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_brand_id"):
        with op.batch_alter_table("listings") as batch:
            batch.create_index("ix_listings_brand_id", ["brand_id"], unique=False)
    if not _index_exists(bind, "listings", "ix_listings_model_id"):
        with op.batch_alter_table("listings") as batch:
            batch.create_index("ix_listings_model_id", ["model_id"], unique=False)


def _upsert_category(bind, *, name: str, slug: str, parent_id: int | None, sort_order: int):
    bind.execute(
        sa.text(
            "INSERT INTO categories(name, slug, parent_id, sort_order, is_active, created_at, updated_at) "
            "SELECT :name, :slug, :parent_id, :sort_order, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP "
            "WHERE NOT EXISTS (SELECT 1 FROM categories WHERE lower(slug)=lower(:slug))"
        ),
        {"name": name, "slug": slug, "parent_id": parent_id, "sort_order": sort_order},
    )
    return bind.execute(sa.text("SELECT id FROM categories WHERE lower(slug)=lower(:slug)"), {"slug": slug}).scalar()


def _upsert_brand(bind, *, name: str, slug: str, category_id: int | None, sort_order: int):
    bind.execute(
        sa.text(
            "INSERT INTO brands(name, slug, category_id, sort_order, is_active, created_at, updated_at) "
            "SELECT :name, :slug, :category_id, :sort_order, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP "
            "WHERE NOT EXISTS (SELECT 1 FROM brands WHERE lower(slug)=lower(:slug))"
        ),
        {"name": name, "slug": slug, "category_id": category_id, "sort_order": sort_order},
    )
    return bind.execute(sa.text("SELECT id FROM brands WHERE lower(slug)=lower(:slug)"), {"slug": slug}).scalar()


def _upsert_model(bind, *, name: str, slug: str, brand_id: int | None, category_id: int | None, sort_order: int):
    bind.execute(
        sa.text(
            "INSERT INTO brand_models(name, slug, brand_id, category_id, sort_order, is_active, created_at, updated_at) "
            "SELECT :name, :slug, :brand_id, :category_id, :sort_order, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP "
            "WHERE NOT EXISTS (SELECT 1 FROM brand_models WHERE lower(slug)=lower(:slug))"
        ),
        {
            "name": name,
            "slug": slug,
            "brand_id": brand_id,
            "category_id": category_id,
            "sort_order": sort_order,
        },
    )


def _seed_taxonomy(bind):
    roots = [
        ("Phones", "phones"),
        ("TVs", "tvs"),
        ("Laptops", "laptops"),
        ("Home Appliances", "home-appliances"),
        ("Furniture", "furniture"),
        ("Fashion", "fashion"),
        ("Beauty", "beauty"),
        ("Baby & Kids", "baby-kids"),
        ("Gaming", "gaming"),
        ("Services", "services"),
        ("Auto Parts", "auto-parts"),
        ("Other", "other"),
    ]
    root_ids: dict[str, int] = {}
    for idx, (name, slug) in enumerate(roots):
        rid = _upsert_category(bind, name=name, slug=slug, parent_id=None, sort_order=idx)
        if rid:
            root_ids[slug] = int(rid)

    leaves = [
        ("iPhone 11", "iphone-11", "phones"),
        ("iPhone 12", "iphone-12", "phones"),
        ("iPhone 13", "iphone-13", "phones"),
        ("iPhone 14", "iphone-14", "phones"),
        ("iPhone 15", "iphone-15", "phones"),
        ("Galaxy S21", "galaxy-s21", "phones"),
        ("Galaxy S22", "galaxy-s22", "phones"),
        ("Galaxy S23", "galaxy-s23", "phones"),
        ("Galaxy S24", "galaxy-s24", "phones"),
        ("Galaxy A14", "galaxy-a14", "phones"),
        ("Galaxy A24", "galaxy-a24", "phones"),
        ("Galaxy A34", "galaxy-a34", "phones"),
        ("Phones Other", "phones-other", "phones"),
        ("LG Smart TVs", "lg-smart-tvs", "tvs"),
        ("Samsung TVs", "samsung-tvs", "tvs"),
        ("Hisense TVs", "hisense-tvs", "tvs"),
        ("TCL TVs", "tcl-tvs", "tvs"),
        ("TVs Other", "tvs-other", "tvs"),
        ("MacBook Air", "macbook-air", "laptops"),
        ("MacBook Pro", "macbook-pro", "laptops"),
        ("HP Laptops", "hp-laptops", "laptops"),
        ("Dell Laptops", "dell-laptops", "laptops"),
        ("Lenovo Laptops", "lenovo-laptops", "laptops"),
        ("Laptops Other", "laptops-other", "laptops"),
        ("Refrigerators", "refrigerators", "home-appliances"),
        ("Washing Machines", "washing-machines", "home-appliances"),
        ("Microwaves", "microwaves", "home-appliances"),
        ("Generators", "generators", "home-appliances"),
        ("Inverters", "inverters", "home-appliances"),
        ("Home Appliances Other", "home-appliances-other", "home-appliances"),
        ("Sofa Sets", "sofa-sets", "furniture"),
        ("Dining Tables", "dining-tables", "furniture"),
        ("TV Consoles", "tv-consoles", "furniture"),
        ("Office Chairs", "office-chairs", "furniture"),
        ("Bed Frames", "bed-frames", "furniture"),
        ("Furniture Other", "furniture-other", "furniture"),
        ("Men Fashion", "men-fashion", "fashion"),
        ("Women Fashion", "women-fashion", "fashion"),
        ("Footwear", "footwear", "fashion"),
        ("Wristwatches", "wristwatches", "fashion"),
        ("Fashion Other", "fashion-other", "fashion"),
        ("Skincare", "skincare", "beauty"),
        ("Makeup", "makeup", "beauty"),
        ("Hair Products", "hair-products", "beauty"),
        ("Fragrances", "fragrances", "beauty"),
        ("Beauty Other", "beauty-other", "beauty"),
        ("Baby Gear", "baby-gear", "baby-kids"),
        ("Toys", "toys", "baby-kids"),
        ("Kids Fashion", "kids-fashion", "baby-kids"),
        ("Baby & Kids Other", "baby-kids-other", "baby-kids"),
        ("PlayStation", "playstation", "gaming"),
        ("Xbox", "xbox", "gaming"),
        ("Nintendo", "nintendo", "gaming"),
        ("Gaming Accessories", "gaming-accessories", "gaming"),
        ("Gaming Other", "gaming-other", "gaming"),
        ("Moving Services", "moving-services", "services"),
        ("Cleaning Services", "cleaning-services", "services"),
        ("Repair Services", "repair-services", "services"),
        ("Services Other", "services-other", "services"),
        ("Car Batteries", "car-batteries", "auto-parts"),
        ("Tyres", "tyres", "auto-parts"),
        ("Engine Oil", "engine-oil", "auto-parts"),
        ("Auto Parts Other", "auto-parts-other", "auto-parts"),
        ("Other / Misc", "other-misc", "other"),
    ]
    leaf_ids: dict[str, int] = {}
    for idx, (name, slug, root_slug) in enumerate(leaves):
        parent_id = root_ids.get(root_slug)
        cid = _upsert_category(bind, name=name, slug=slug, parent_id=parent_id, sort_order=idx)
        if cid:
            leaf_ids[slug] = int(cid)

    brand_defs = [
        ("Apple", "apple", "phones"),
        ("Samsung", "samsung", "phones"),
        ("Xiaomi", "xiaomi", "phones"),
        ("Tecno", "tecno", "phones"),
        ("Infinix", "infinix", "phones"),
        ("LG", "lg", "tvs"),
        ("Hisense", "hisense", "tvs"),
        ("TCL", "tcl", "tvs"),
        ("Sony", "sony", "tvs"),
        ("HP", "hp", "laptops"),
        ("Dell", "dell", "laptops"),
        ("Lenovo", "lenovo", "laptops"),
    ]
    brand_ids: dict[str, int] = {}
    for idx, (name, slug, root_slug) in enumerate(brand_defs):
        brand_id = _upsert_brand(bind, name=name, slug=slug, category_id=root_ids.get(root_slug), sort_order=idx)
        if brand_id:
            brand_ids[slug] = int(brand_id)

    model_defs = [
        ("iPhone 11", "apple-iphone-11", "apple", "phones"),
        ("iPhone 12", "apple-iphone-12", "apple", "phones"),
        ("iPhone 13", "apple-iphone-13", "apple", "phones"),
        ("iPhone 14", "apple-iphone-14", "apple", "phones"),
        ("iPhone 15", "apple-iphone-15", "apple", "phones"),
        ("Galaxy S23", "samsung-galaxy-s23", "samsung", "phones"),
        ("Galaxy S24", "samsung-galaxy-s24", "samsung", "phones"),
        ("Galaxy A14", "samsung-galaxy-a14", "samsung", "phones"),
        ("Galaxy A24", "samsung-galaxy-a24", "samsung", "phones"),
        ("LG OLED", "lg-oled", "lg", "tvs"),
        ("Samsung QLED", "samsung-qled", "samsung", "tvs"),
        ("Hisense UHD", "hisense-uhd", "hisense", "tvs"),
        ("TCL 4K", "tcl-4k", "tcl", "tvs"),
        ("MacBook Air M2", "macbook-air-m2", "apple", "laptops"),
        ("MacBook Pro M3", "macbook-pro-m3", "apple", "laptops"),
        ("HP Pavilion", "hp-pavilion", "hp", "laptops"),
        ("Dell Inspiron", "dell-inspiron", "dell", "laptops"),
        ("Lenovo ThinkPad", "lenovo-thinkpad", "lenovo", "laptops"),
    ]
    for idx, (name, slug, brand_slug, root_slug) in enumerate(model_defs):
        _upsert_model(
            bind,
            name=name,
            slug=slug,
            brand_id=brand_ids.get(brand_slug),
            category_id=root_ids.get(root_slug),
            sort_order=idx,
        )

    # Soft backfill existing listings.
    fallback = leaf_ids.get("other-misc")
    phones_leaf = leaf_ids.get("phones-other") or fallback
    tv_leaf = leaf_ids.get("tvs-other") or fallback
    laptop_leaf = leaf_ids.get("laptops-other") or fallback
    furniture_leaf = leaf_ids.get("furniture-other") or fallback
    appliance_leaf = leaf_ids.get("home-appliances-other") or fallback
    fashion_leaf = leaf_ids.get("fashion-other") or fallback
    gaming_leaf = leaf_ids.get("gaming-other") or fallback

    if phones_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%phone%' OR "
                "lower(coalesce(title,'')) LIKE '%iphone%' OR "
                "lower(coalesce(title,'')) LIKE '%samsung%' OR "
                "lower(coalesce(title,'')) LIKE '%galaxy%')"
            ),
            {"cid": int(phones_leaf)},
        )
    if tv_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%tv%' OR "
                "lower(coalesce(title,'')) LIKE '%tv%' OR "
                "lower(coalesce(title,'')) LIKE '%hisense%' OR "
                "lower(coalesce(title,'')) LIKE '%tcl%')"
            ),
            {"cid": int(tv_leaf)},
        )
    if laptop_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%laptop%' OR "
                "lower(coalesce(title,'')) LIKE '%macbook%' OR "
                "lower(coalesce(title,'')) LIKE '%thinkpad%' OR "
                "lower(coalesce(title,'')) LIKE '%inspiron%')"
            ),
            {"cid": int(laptop_leaf)},
        )
    if furniture_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%furniture%' OR "
                "lower(coalesce(title,'')) LIKE '%sofa%' OR "
                "lower(coalesce(title,'')) LIKE '%dining%' OR "
                "lower(coalesce(title,'')) LIKE '%chair%')"
            ),
            {"cid": int(furniture_leaf)},
        )
    if appliance_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%appliance%' OR "
                "lower(coalesce(title,'')) LIKE '%fridge%' OR "
                "lower(coalesce(title,'')) LIKE '%washing%' OR "
                "lower(coalesce(title,'')) LIKE '%generator%' OR "
                "lower(coalesce(title,'')) LIKE '%inverter%')"
            ),
            {"cid": int(appliance_leaf)},
        )
    if fashion_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%fashion%' OR "
                "lower(coalesce(title,'')) LIKE '%shoe%' OR "
                "lower(coalesce(title,'')) LIKE '%watch%')"
            ),
            {"cid": int(fashion_leaf)},
        )
    if gaming_leaf:
        bind.execute(
            sa.text(
                "UPDATE listings SET category_id=:cid "
                "WHERE category_id IS NULL AND ("
                "lower(coalesce(category,'')) LIKE '%gaming%' OR "
                "lower(coalesce(title,'')) LIKE '%ps5%' OR "
                "lower(coalesce(title,'')) LIKE '%playstation%' OR "
                "lower(coalesce(title,'')) LIKE '%xbox%')"
            ),
            {"cid": int(gaming_leaf)},
        )
    if fallback:
        bind.execute(
            sa.text("UPDATE listings SET category_id=:cid WHERE category_id IS NULL"),
            {"cid": int(fallback)},
        )


def upgrade():
    bind = op.get_bind()
    _add_user_profile_photo_column(bind)
    _create_taxonomy_tables(bind)
    _add_listing_taxonomy_columns(bind)
    _seed_taxonomy(bind)


def downgrade():
    # Non-destructive downgrade.
    pass
