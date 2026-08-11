from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Category
from app.schemas.categories import CategoryCreate, CategoryUpdate
from app.services.category_presets import preset_definition
from app.services.common import normalize_name


async def get_category(session: AsyncSession, user_id: UUID, category_id: UUID) -> Category:
    category = await session.scalar(select(Category).where(Category.id == category_id, Category.user_id == user_id))
    if category is None:
        raise DomainError(404, "category not found", "category_not_found")
    return category


async def list_categories(session: AsyncSession, user_id: UUID, include_deleted: bool = False) -> list[Category]:
    query = select(Category).where(Category.user_id == user_id)
    if not include_deleted:
        query = query.where(Category.deleted_at.is_(None))
    query = query.order_by(Category.income.asc(), Category.sort_order.asc(), Category.name.asc())
    return list((await session.scalars(query)).all())


async def create_category(session: AsyncSession, user_id: UUID, payload: CategoryCreate) -> Category:
    category = Category(
        user_id=user_id,
        name=payload.name.strip(),
        normalized_name=normalize_name(payload.name),
        income=payload.income,
        icon_identifier=payload.icon_identifier,
        color=payload.color,
        sort_order=payload.sort_order,
        preset_key=None,
    )
    await _ensure_unique(session, user_id, category.income, category.normalized_name)
    session.add(category)
    try:
        await session.commit()
    except IntegrityError as exc:
        await session.rollback()
        raise DomainError(409, "an active category with this name already exists", "duplicate_category") from exc
    await session.refresh(category)
    return category


async def update_category(session: AsyncSession, user_id: UUID, category_id: UUID, payload: CategoryUpdate) -> Category:
    category = await get_category(session, user_id, category_id)
    if category.deleted_at is not None:
        raise DomainError(409, "deleted categories cannot be edited", "category_deleted")
    if category.preset_key is not None:
        raise DomainError(409, "built-in categories cannot be edited", "preset_category_read_only")

    values = payload.model_dump(exclude_unset=True)
    name = values.get("name", category.name)
    income = values.get("income", category.income)
    await _ensure_unique(session, user_id, income, normalize_name(name), exclude_id=category.id)
    if "name" in values:
        category.name = str(name).strip()
        category.normalized_name = normalize_name(name)
    for key in ("income", "icon_identifier", "color", "sort_order"):
        if key in values and values[key] is not None:
            setattr(category, key, values[key])
    await session.commit()
    await session.refresh(category)
    return category


async def activate_category_preset(
    session: AsyncSession,
    user_id: UUID,
    preset_key: str,
    requested_income: bool | None = None,
    display_name: str | None = None,
) -> Category:
    preset = preset_definition(preset_key)
    if preset is None:
        raise DomainError(422, "unknown category preset", "unknown_category_preset")
    if requested_income is not None and requested_income != preset.income:
        raise DomainError(422, "category preset type does not match the requested income flag", "preset_type_mismatch")

    requested_name = display_name.strip() if display_name and display_name.strip() else preset.name

    existing = await session.scalar(
        select(Category).where(Category.user_id == user_id, Category.preset_key == preset.key)
    )
    if existing is not None:
        if existing.deleted_at is not None:
            await _ensure_unique(session, user_id, preset.income, normalize_name(requested_name))
            await _ensure_unique(session, user_id, preset.income, normalize_name(preset.name))
            existing.deleted_at = None
            existing.name = preset.name
            existing.normalized_name = normalize_name(preset.name)
            existing.income = preset.income
            existing.icon_identifier = preset.icon_identifier
            existing.color = preset.color
            await session.commit()
            await session.refresh(existing)
        return existing

    await _ensure_unique(session, user_id, preset.income, normalize_name(requested_name))
    await _ensure_unique(session, user_id, preset.income, normalize_name(preset.name))
    last_sort_order = await session.scalar(
        select(Category.sort_order)
        .where(Category.user_id == user_id, Category.income.is_(preset.income), Category.deleted_at.is_(None))
        .order_by(Category.sort_order.desc())
        .limit(1)
    )
    category = Category(
        user_id=user_id,
        name=preset.name,
        normalized_name=normalize_name(preset.name),
        income=preset.income,
        icon_identifier=preset.icon_identifier,
        color=preset.color,
        sort_order=(last_sort_order + 1) if last_sort_order is not None else 0,
        preset_key=preset.key,
    )
    session.add(category)
    try:
        await session.commit()
    except IntegrityError as exc:
        await session.rollback()
        raise DomainError(409, "an active category with this name already exists", "duplicate_category") from exc
    await session.refresh(category)
    return category


async def soft_delete_category(session: AsyncSession, user_id: UUID, category_id: UUID) -> Category:
    category = await get_category(session, user_id, category_id)
    category.deleted_at = category.updated_at
    await session.commit()
    await session.refresh(category)
    return category


async def _ensure_unique(
    session: AsyncSession,
    user_id: UUID,
    income: bool,
    normalized_name: str,
    exclude_id: UUID | None = None,
) -> None:
    query = select(Category.id).where(
        Category.user_id == user_id,
        Category.income.is_(income),
        Category.normalized_name == normalized_name,
        Category.deleted_at.is_(None),
    )
    if exclude_id is not None:
        query = query.where(Category.id != exclude_id)
    if await session.scalar(query) is not None:
        raise DomainError(409, "an active category with this name already exists", "duplicate_category")
