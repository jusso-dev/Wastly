#!/usr/bin/env python3
"""Build Wastly's compact offline catalogue from official FSANZ workbooks."""

from __future__ import annotations

import argparse
import hashlib
import json
import posixpath
import re
import sys
import unicodedata
import zipfile
from pathlib import Path
from xml.etree import ElementTree


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"

AUSNUT_SHA256 = "374650afc59951009d5ddf48fe35f712467458eb07eef513ea9f54c8f110f317"
AFCD_SHA256 = "14cb3e73dbf58987b440e6299624c0fefd7a4e61591fc1f753995d9534e0efc9"
EXPECTED_AUSNUT_ROWS = 3_741
EXPECTED_AFCD_ROWS = 1_588
EXPECTED_UNION_ROWS = 4_128

LIMITATION_STATEMENT = (
    "There are limitations associated with food composition databases. Food composition data "
    "used in the database or databases may represent an average of the nutrient content of a "
    "particular sample of foods and ingredients, determined at a particular time. The nutrient "
    "composition of foods and ingredients can vary substantially between batches and brands "
    "because of a number of factors, including changes in season, processing practices and "
    "ingredient source, and methods of calculation."
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def column_number(reference: str) -> int:
    match = re.match(r"[A-Z]+", reference)
    if not match:
        raise ValueError(f"Invalid cell reference: {reference}")
    result = 0
    for character in match.group(0):
        result = result * 26 + ord(character) - ord("A") + 1
    return result


def shared_strings(archive: zipfile.ZipFile) -> list[str]:
    try:
        root = ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    return ["".join(item.itertext()) for item in root.findall(f"{{{MAIN_NS}}}si")]


def worksheet_path(archive: zipfile.ZipFile, sheet_name: str) -> str:
    workbook = ElementTree.fromstring(archive.read("xl/workbook.xml"))
    relationships = ElementTree.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    targets = {
        relationship.attrib["Id"]: relationship.attrib["Target"]
        for relationship in relationships.findall(f"{{{PACKAGE_REL_NS}}}Relationship")
    }
    for sheet in workbook.findall(f".//{{{MAIN_NS}}}sheet"):
        if sheet.attrib.get("name") == sheet_name:
            relation_id = sheet.attrib[f"{{{REL_NS}}}id"]
            target = targets[relation_id].lstrip("/")
            return target if target.startswith("xl/") else posixpath.normpath(f"xl/{target}")
    raise ValueError(f"Worksheet not found: {sheet_name}")


def cell_value(cell: ElementTree.Element, strings: list[str]) -> str | float | None:
    cell_type = cell.attrib.get("t")
    if cell_type == "inlineStr":
        inline = cell.find(f"{{{MAIN_NS}}}is")
        return "".join(inline.itertext()) if inline is not None else None
    value = cell.findtext(f"{{{MAIN_NS}}}v")
    if value is None:
        return None
    if cell_type == "s":
        return strings[int(value)]
    if cell_type in {"str", "e"}:
        return value
    return float(value)


def food_rows(path: Path, sheet_name: str, key_column: int) -> list[dict[str, object]]:
    foods: list[dict[str, object]] = []
    with zipfile.ZipFile(path) as archive:
        strings = shared_strings(archive)
        sheet_path = worksheet_path(archive, sheet_name)
        with archive.open(sheet_path) as worksheet:
            for _, row in ElementTree.iterparse(worksheet, events=("end",)):
                if row.tag != f"{{{MAIN_NS}}}row":
                    continue
                if int(row.attrib.get("r", "0")) < 4:
                    row.clear()
                    continue
                cells = {
                    column_number(cell.attrib["r"]): cell_value(cell, strings)
                    for cell in row.findall(f"{{{MAIN_NS}}}c")
                }
                key = str(cells.get(key_column, "")).strip()
                name = unicodedata.normalize("NFC", str(cells.get(4, "")).strip())
                energy = cells.get(5)
                if not key or not name or not isinstance(energy, float):
                    raise ValueError(f"Invalid food row {row.attrib.get('r')} in {path.name}")
                foods.append(
                    {
                        "catalogID": f"fsanz:{key}",
                        "name": name,
                        "barcode": "",
                        "kilojoulesPer100g": int(energy) if energy.is_integer() else energy,
                    }
                )
                row.clear()
    return foods


def require_source(path: Path, expected_hash: str) -> None:
    actual_hash = sha256(path)
    if actual_hash != expected_hash:
        raise ValueError(
            f"Unexpected source checksum for {path}: {actual_hash}; expected {expected_hash}"
        )


def build_catalog(ausnut_path: Path, afcd_path: Path) -> list[dict[str, object]]:
    require_source(ausnut_path, AUSNUT_SHA256)
    require_source(afcd_path, AFCD_SHA256)

    ausnut = food_rows(ausnut_path, "Food nutrient profiles", key_column=2)
    afcd = food_rows(afcd_path, "All solids & liquids per 100 g", key_column=1)
    if len(ausnut) != EXPECTED_AUSNUT_ROWS or len(afcd) != EXPECTED_AFCD_ROWS:
        raise ValueError(f"Unexpected row counts: AUSNUT={len(ausnut)}, AFCD={len(afcd)}")

    # AUSNUT is the newer survey profile. AFCD contributes reference foods absent from it.
    by_id = {food["catalogID"]: food for food in afcd}
    by_id.update({food["catalogID"]: food for food in ausnut})
    foods = sorted(by_id.values(), key=lambda food: (str(food["name"]).casefold(), food["catalogID"]))
    if len(foods) != EXPECTED_UNION_ROWS:
        raise ValueError(f"Unexpected union row count: {len(foods)}")
    return foods


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ausnut", type=Path, help="AUSNUT 2023 Food nutrient profiles XLSX")
    parser.add_argument("afcd", type=Path, help="AFCD Release 3 Nutrient profiles XLSX")
    parser.add_argument("output", type=Path, help="Generated seed-foods.json")
    args = parser.parse_args()

    foods = build_catalog(args.ausnut, args.afcd)
    payload = {
        "metadata": {
            "version": 1,
            "title": "AUSNUT 2023 and Australian Food Composition Database Release 3",
            "attribution": "Food Standards Australia New Zealand (FSANZ)",
            "license": "FSANZ Data User Licence Agreement based on CC BY-SA 3.0 Australia",
            "licenseURL": "https://www.foodstandards.gov.au/science-data/monitoringnutrients/afcd/datauserlicenceagreement",
            "sourceURL": "https://www.foodstandards.gov.au/science-data/food-nutrient-databases",
            "changes": "Combined by public food key, preferred AUSNUT 2023 overlaps, and retained only food name and energy per 100 g.",
            "limitation": LIMITATION_STATEMENT,
            "territoryNotice": "This work is based on Australian data. Australian data may not be appropriate for use in other countries.",
        },
        "foods": foods,
    }
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(foods):,} foods to {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
