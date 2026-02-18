from __future__ import annotations

import re
from typing import Any


VEHICLES_GROUP_SLUG = "vehicles"
POWER_ENERGY_GROUP_SLUG = "power-energy"
REAL_ESTATE_GROUP_SLUG = "real-estate"


def slugify(value: str) -> str:
    raw = (value or "").strip().lower()
    if not raw:
        return ""
    raw = re.sub(r"[^a-z0-9]+", "-", raw)
    raw = re.sub(r"-{2,}", "-", raw)
    return raw.strip("-")


VEHICLES_SUBCATEGORIES = [
    "Cars",
    "Buses & Microbuses",
    "Trucks & Trailers",
    "Motorcycles & Scooters",
    "Construction & Heavy Machinery",
    "Watercraft & Boats",
    "Vehicle Parts & Accessories",
]

POWER_ENERGY_SUBCATEGORIES = [
    "Inverters",
    "Solar Panels",
    "Solar Batteries",
    "Lithium Batteries",
    "LiFePO4 Batteries",
    "Gel Batteries",
    "Tall Tubular Batteries",
    "Charge Controllers",
    "Solar Accessories",
    "Solar Installation Services",
    "Solar Bundle",
]

REAL_ESTATE_SUBCATEGORIES = [
    "House for Rent",
    "House for Sale",
    "Land for Sale",
]

CATEGORY_GROUPS = [
    {
        "name": "Vehicles",
        "slug": VEHICLES_GROUP_SLUG,
        "subcategories": [
            {"name": name, "slug": slugify(name)} for name in VEHICLES_SUBCATEGORIES
        ],
    },
    {
        "name": "Power & Energy",
        "slug": POWER_ENERGY_GROUP_SLUG,
        "subcategories": [
            {"name": name, "slug": slugify(name)} for name in POWER_ENERGY_SUBCATEGORIES
        ],
    },
    {
        "name": "Real Estate",
        "slug": REAL_ESTATE_GROUP_SLUG,
        "subcategories": [
            {"name": name, "slug": slugify(name)} for name in REAL_ESTATE_SUBCATEGORIES
        ],
    },
]


def _text(value: Any) -> str:
    return str(value or "").strip()


def _as_int(value: Any) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(str(value).strip())
    except Exception:
        return None


def _as_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(str(value).strip())
    except Exception:
        return None


def _as_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return int(value) == 1
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "y", "on"):
        return True
    if text in ("0", "false", "no", "n", "off"):
        return False
    return None


def _normalize_select(value: Any, allowed: list[str]) -> str:
    text = _text(value)
    if not text:
        return ""
    by_key = {option.strip().lower(): option for option in allowed}
    return by_key.get(text.lower(), "")


def _field(
    key: str,
    label: str,
    *,
    field_type: str = "text",
    required: bool = False,
    options: list[str] | None = None,
    encouraged: bool = False,
) -> dict[str, Any]:
    return {
        "key": key,
        "label": label,
        "type": field_type,
        "required": bool(required),
        "encouraged": bool(encouraged),
        "options": options or [],
    }


CAR_FIELDS = [
    _field("make", "Make", required=True),
    _field("model", "Model", required=True),
    _field("year_of_manufacture", "Year of Manufacture", field_type="number", required=True),
    _field(
        "condition",
        "Condition",
        field_type="select",
        required=True,
        options=["Brand New", "Used - Like New", "Used - Good", "Used - Fair"],
    ),
    _field("transmission", "Transmission", field_type="select", required=True, options=["Automatic", "Manual", "CVT", "Semi-Automatic"]),
    _field("fuel_type", "Fuel Type", field_type="select", required=True, options=["Petrol", "Diesel", "Hybrid", "Electric", "CNG"]),
    _field("drivetrain", "Drivetrain", field_type="select", required=True, options=["FWD", "RWD", "AWD", "4WD"]),
    _field(
        "body_type",
        "Body Type",
        field_type="select",
        required=True,
        options=["Sedan", "SUV", "Hatchback", "Coupe", "Convertible", "Pickup", "Van", "Wagon", "Minivan"],
    ),
    _field("mileage", "Mileage", field_type="number", required=True),
    _field("color", "Color", required=True),
    _field("registered_car", "Registered Car", field_type="boolean", required=True),
    _field("vin", "VIN", encouraged=True),
    _field("engine_size", "Engine Size"),
    _field("horse_power", "Horse Power", field_type="number"),
    _field("number_of_cylinders", "Number of Cylinders", field_type="number"),
    _field("interior_color", "Interior Color"),
    _field("exchange_possible", "Exchange Possible", field_type="boolean"),
    _field("accident_history", "Accident History", field_type="select", options=["None", "Minor", "Major"]),
    _field("service_history_available", "Service History Available", field_type="boolean"),
    _field("location_verification_badge", "Location Verification Badge", field_type="boolean"),
    _field("inspection_request_option", "Inspection Request Option", field_type="boolean"),
    _field("delivery_available", "Delivery Available", field_type="boolean"),
    _field("financing_option", "Financing Option", field_type="boolean"),
]

GENERIC_VEHICLE_FIELDS = [
    _field("make", "Make"),
    _field("model", "Model"),
    _field("year_of_manufacture", "Year of Manufacture", field_type="number"),
    _field("condition", "Condition"),
    _field("delivery_available", "Delivery Available", field_type="boolean"),
    _field("inspection_request_option", "Inspection Request Option", field_type="boolean"),
    _field("financing_option", "Financing Option", field_type="boolean"),
]

SOLAR_BUNDLE_FIELDS = [
    _field("inverter_brand_capacity", "Inverter Brand & Capacity", required=True),
    _field(
        "battery_type",
        "Battery Type",
        field_type="select",
        required=True,
        options=["Lithium", "Gel", "Tubular", "LiFePO4"],
    ),
    _field("battery_capacity_ah", "Battery Capacity (Ah)", field_type="number", required=True),
    _field("number_of_batteries", "Number of Batteries", field_type="number", required=True),
    _field("solar_panel_wattage", "Solar Panel Wattage", field_type="number", required=True),
    _field("number_of_panels", "Number of Panels", field_type="number", required=True),
    _field("included_accessories", "Included Accessories", required=True),
    _field("installation_included", "Installation Included", field_type="boolean", required=True),
    _field("warranty_length", "Warranty Length", required=True),
    _field("load_capacity", "Load Capacity", required=True),
    _field("estimated_daily_output", "Estimated Daily Output", required=True),
    _field("delivery_included", "Delivery Included", field_type="boolean", required=True),
    _field("financing_option", "Financing Option", field_type="boolean"),
]

GENERIC_ENERGY_FIELDS = [
    _field("battery_type", "Battery Type"),
    _field("inverter_capacity", "Inverter Capacity"),
    _field("lithium_only", "Lithium Only", field_type="boolean"),
    _field("delivery_available", "Delivery Available", field_type="boolean"),
    _field("financing_option", "Financing Option", field_type="boolean"),
]

REAL_ESTATE_COMMON_FIELDS = [
    _field(
        "property_type",
        "Property Type",
        field_type="select",
        required=True,
        options=["Rent", "Sale", "Land"],
    ),
    _field("state", "State", required=True),
    _field("city", "City", required=True),
    _field("area", "Area", required=True),
    _field("price", "Price", field_type="number", required=True),
    _field("title_headline", "Title/Headline", required=True),
    _field("description", "Description", required=True),
]

REAL_ESTATE_HOUSE_FIELDS = [
    _field("bedrooms", "Bedrooms", field_type="number", required=True),
    _field("bathrooms", "Bathrooms", field_type="number", required=True),
    _field("toilets", "Toilets", field_type="number", required=True),
    _field("parking_spaces", "Parking Spaces", field_type="number", required=True),
    _field("furnished", "Furnished", field_type="boolean", required=True),
    _field("serviced", "Serviced", field_type="boolean", required=True),
    _field("newly_built", "Newly Built", field_type="boolean", required=True),
    _field("total_floors", "Total Floors", field_type="number"),
    _field("property_size_sqm", "Property Size (sqm)", field_type="number"),
]

REAL_ESTATE_LAND_FIELDS = [
    _field("land_size", "Land Size", field_type="number", required=True),
    _field(
        "land_size_unit",
        "Land Size Unit",
        field_type="select",
        required=True,
        options=["sqm", "plots"],
    ),
    _field(
        "title_document_type",
        "Title Document Type",
        field_type="select",
        required=True,
        options=["C of O", "Gov Consent", "Deed", "Survey", "Unknown"],
    ),
    _field(
        "topography",
        "Topography",
        field_type="select",
        required=True,
        options=["Dry", "Swampy", "Mixed"],
    ),
    _field("access_road", "Access Road", field_type="boolean", required=True),
]


def schema_for_category(*, group_slug: str, category_slug: str) -> dict[str, Any]:
    gslug = slugify(group_slug)
    cslug = slugify(category_slug)
    if gslug == VEHICLES_GROUP_SLUG:
        if cslug == "cars":
            fields = CAR_FIELDS
        else:
            fields = GENERIC_VEHICLE_FIELDS
        return {
            "metadata_key": "vehicle_metadata",
            "listing_type_hint": "vehicle",
            "fields": fields,
        }
    if gslug == POWER_ENERGY_GROUP_SLUG:
        if cslug == "solar-bundle":
            fields = SOLAR_BUNDLE_FIELDS
        else:
            fields = GENERIC_ENERGY_FIELDS
        return {
            "metadata_key": "energy_metadata",
            "listing_type_hint": "energy",
            "fields": fields,
        }
    if gslug == REAL_ESTATE_GROUP_SLUG:
        if cslug == "land-for-sale":
            fields = [*REAL_ESTATE_COMMON_FIELDS, *REAL_ESTATE_LAND_FIELDS]
        else:
            fields = [*REAL_ESTATE_COMMON_FIELDS, *REAL_ESTATE_HOUSE_FIELDS]
        return {
            "metadata_key": "real_estate_metadata",
            "listing_type_hint": "real_estate",
            "fields": fields,
        }
    return {
        "metadata_key": "",
        "listing_type_hint": "declutter",
        "fields": [],
    }


def _validate_required_fields(fields: list[dict[str, Any]], payload: dict[str, Any], errors: list[str]) -> None:
    for field in fields:
        if not field.get("required"):
            continue
        key = str(field.get("key") or "")
        value = payload.get(key)
        field_type = str(field.get("type") or "text")
        if field_type == "boolean":
            if _as_bool(value) is None:
                errors.append(f"{key} is required")
        elif field_type == "number":
            if _as_float(value) is None:
                errors.append(f"{key} is required")
        elif field_type == "select":
            options = [str(x) for x in (field.get("options") or [])]
            if not _normalize_select(value, options):
                errors.append(f"{key} is required")
        else:
            if not _text(value):
                errors.append(f"{key} is required")


def _sanitize_by_fields(fields: list[dict[str, Any]], payload: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for field in fields:
        key = str(field.get("key") or "")
        if not key:
            continue
        value = payload.get(key)
        field_type = str(field.get("type") or "text")
        if field_type == "boolean":
            parsed = _as_bool(value)
            if parsed is not None:
                out[key] = bool(parsed)
            continue
        if field_type == "number":
            number = _as_float(value)
            if number is None:
                continue
            as_int = int(number)
            out[key] = as_int if float(as_int) == float(number) else float(number)
            continue
        if field_type == "select":
            options = [str(x) for x in (field.get("options") or [])]
            text = _normalize_select(value, options)
            if text:
                out[key] = text
            continue
        text = _text(value)
        if text:
            out[key] = text
    return out


def validate_category_metadata(
    *,
    group_slug: str,
    category_slug: str,
    payload: dict[str, Any] | None,
) -> dict[str, Any]:
    schema = schema_for_category(group_slug=group_slug, category_slug=category_slug)
    metadata_key = str(schema.get("metadata_key") or "")
    fields = list(schema.get("fields") or [])
    listing_type_hint = str(schema.get("listing_type_hint") or "declutter")

    clean_payload = dict(payload or {})
    errors: list[str] = []

    if metadata_key:
        _validate_required_fields(fields, clean_payload, errors)

    metadata = _sanitize_by_fields(fields, clean_payload)
    vehicle_metadata: dict[str, Any] = {}
    energy_metadata: dict[str, Any] = {}
    real_estate_metadata: dict[str, Any] = {}
    if metadata_key == "vehicle_metadata":
        vehicle_metadata = metadata
    if metadata_key == "energy_metadata":
        energy_metadata = metadata
    if metadata_key == "real_estate_metadata":
        real_estate_metadata = metadata

    make = _text(vehicle_metadata.get("make"))
    model = _text(vehicle_metadata.get("model"))
    year = _as_int(vehicle_metadata.get("year_of_manufacture"))
    battery_type = _text(energy_metadata.get("battery_type"))
    inverter_capacity = _text(
        energy_metadata.get("inverter_capacity")
        or energy_metadata.get("inverter_brand_capacity")
    )

    lithium_only = False
    lithium_flag = _as_bool(energy_metadata.get("lithium_only"))
    if lithium_flag is not None:
        lithium_only = bool(lithium_flag)
    elif battery_type.strip().lower() in ("lithium", "lifepo4"):
        lithium_only = True

    delivery_available = _as_bool(
        vehicle_metadata.get("delivery_available")
        if vehicle_metadata
        else energy_metadata.get("delivery_available")
    )
    if delivery_available is None:
        delivery_available = _as_bool(energy_metadata.get("delivery_included"))

    inspection_required = _as_bool(vehicle_metadata.get("inspection_request_option"))
    location_verified = _as_bool(vehicle_metadata.get("location_verification_badge"))
    financing_option = _as_bool(
        vehicle_metadata.get("financing_option")
        if vehicle_metadata
        else energy_metadata.get("financing_option")
    )

    bundle_badge = bool(
        slugify(group_slug) == POWER_ENERGY_GROUP_SLUG and slugify(category_slug) == "solar-bundle"
    )

    property_type = _text(real_estate_metadata.get("property_type"))
    category_key = slugify(category_slug)
    if not property_type:
        if category_key == "house-for-rent":
            property_type = "Rent"
        elif category_key == "house-for-sale":
            property_type = "Sale"
        elif category_key == "land-for-sale":
            property_type = "Land"
    bedrooms = _as_int(real_estate_metadata.get("bedrooms"))
    bathrooms = _as_int(real_estate_metadata.get("bathrooms"))
    furnished = _as_bool(real_estate_metadata.get("furnished"))
    serviced = _as_bool(real_estate_metadata.get("serviced"))
    land_size = _as_float(real_estate_metadata.get("land_size"))
    title_document_type = _text(real_estate_metadata.get("title_document_type"))

    return {
        "ok": len(errors) == 0,
        "errors": errors,
        "listing_type_hint": listing_type_hint,
        "vehicle_metadata": vehicle_metadata,
        "energy_metadata": energy_metadata,
        "real_estate_metadata": real_estate_metadata,
        "derived": {
            "vehicle_make": make,
            "vehicle_model": model,
            "vehicle_year": year,
            "battery_type": battery_type,
            "inverter_capacity": inverter_capacity,
            "lithium_only": bool(lithium_only),
            "bundle_badge": bundle_badge,
            "delivery_available": delivery_available,
            "inspection_required": inspection_required,
            "location_verified": location_verified,
            "inspection_request_enabled": inspection_required,
            "financing_option": financing_option,
            "property_type": property_type,
            "bedrooms": bedrooms,
            "bathrooms": bathrooms,
            "furnished": furnished,
            "serviced": serviced,
            "land_size": land_size,
            "title_document_type": title_document_type,
        },
    }
