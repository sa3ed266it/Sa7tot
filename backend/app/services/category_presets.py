from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class CategoryPresetDefinition:
    key: str
    name: str
    income: bool
    icon_identifier: str
    color: str


_PRESETS = (
    CategoryPresetDefinition("expense.food", "Food", False, "sf:fork.knife", "#279AF4"),
    CategoryPresetDefinition("expense.transport", "Transport", False, "sf:tram.fill", "#61C7FA"),
    CategoryPresetDefinition("expense.rent", "Rent", False, "sf:house.fill", "#A6678A"),
    CategoryPresetDefinition("expense.groceries", "Groceries", False, "sf:cart.fill", "#5FAF9F"),
    CategoryPresetDefinition("expense.family", "Family", False, "sf:person.2.fill", "#ED80A2"),
    CategoryPresetDefinition("expense.utilities", "Utilities", False, "sf:lightbulb.fill", "#F6D24A"),
    CategoryPresetDefinition("expense.fashion", "Fashion", False, "sf:tshirt.fill", "#C56AF7"),
    CategoryPresetDefinition("expense.healthcare", "Healthcare", False, "sf:cross.case.fill", "#E34D63"),
    CategoryPresetDefinition("expense.pets", "Pets", False, "sf:pawprint.fill", "#84B4EB"),
    CategoryPresetDefinition("expense.sneakers", "Sneakers", False, "sf:shoe.2.fill", "#F3BF56"),
    CategoryPresetDefinition("expense.gifts", "Gifts", False, "sf:gift.fill", "#EC7A58"),
    CategoryPresetDefinition("income.paycheck", "Paycheck", True, "sf:banknote.fill", "#35A77A"),
    CategoryPresetDefinition("income.allowance", "Allowance", True, "sf:banknote.fill", "#7CB0AA"),
    CategoryPresetDefinition("income.part_time", "Part-Time", True, "sf:briefcase.fill", "#6E7BF1"),
    CategoryPresetDefinition("income.investments", "Investments", True, "sf:chart.bar.fill", "#A0ACF9"),
    CategoryPresetDefinition("income.gifts", "Gifts", True, "sf:gift.fill", "#F1AF8A"),
    CategoryPresetDefinition("income.tips", "Tips", True, "sf:sparkles", "#C38D5D"),
)

PRESET_CATALOG: dict[str, CategoryPresetDefinition] = {preset.key: preset for preset in _PRESETS}


def preset_definition(preset_key: str) -> CategoryPresetDefinition | None:
    return PRESET_CATALOG.get(preset_key)
