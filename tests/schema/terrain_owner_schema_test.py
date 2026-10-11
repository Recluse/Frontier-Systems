"""Validate terrain-only JSON contracts against output of the Godot domain suite.

Development prerequisite: jsonschema==4.23.0. No network schema resolution.
Run terrain_material_owner_test.gd with the repository bounded runner first.
"""
from copy import deepcopy
from pathlib import Path
import json

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_NAMES = (
    "terrain-material-state-v1",
    "terrain-material-transfer-plan-v1",
    "terrain-owner-intent-v1",
    "terrain-owner-seed-v1",
    "terrain-material-owner-v1",
)
schemas = {
    name: json.loads((ROOT / "docs/schema" / f"{name}.schema.json").read_text(encoding="utf-8-sig"))
    for name in SCHEMA_NAMES
}
registry = Registry().with_resources(
    (schema["$id"], Resource.from_contents(schema)) for schema in schemas.values()
)
validators = {}
for name, schema in schemas.items():
    Draft202012Validator.check_schema(schema)
    validators[name] = Draft202012Validator(schema, registry=registry)

fixtures = json.loads(
    (ROOT / "var/ci/godot/terrain-schema-fixtures.json").read_text(encoding="utf-8")
)
validators["terrain-material-owner-v1"].validate(fixtures["owner"])
for intent in fixtures["intents"]:
    validators["terrain-owner-intent-v1"].validate(intent)
for seed in fixtures["seeds"]:
    validators["terrain-owner-seed-v1"].validate(seed)


def rejects(name, record):
    if validators[name].is_valid(record):
        raise AssertionError(f"{name} accepted invalid shape: {record}")


for field, value in (("amount_milligrams", 1.5), ("sequence", 0), ("cell_id", " ")):
    invalid = deepcopy(fixtures["intents"][0])
    invalid[field] = value
    rejects("terrain-owner-intent-v1", invalid)
invalid = deepcopy(fixtures["intents"][1])
invalid["transfer_id"] = ""
rejects("terrain-owner-intent-v1", invalid)
invalid = deepcopy(fixtures["intents"][0])
invalid["after"] = {}
rejects("terrain-owner-intent-v1", invalid)
invalid = deepcopy(fixtures["seeds"][0])
invalid["state"]["state_revision"] = 1
rejects("terrain-owner-seed-v1", invalid)
invalid = deepcopy(fixtures["owner"])
invalid["transfers"]["invented-transfer"] = next(iter(invalid["transfers"].values()))
rejects("terrain-material-owner-v1", invalid)
invalid = deepcopy(fixtures["owner"])
invalid["receipts"] *= 33
rejects("terrain-material-owner-v1", invalid)
print("Five terrain schemas and actual owner/intent/seed fixtures passed; eight invalid shapes rejected.")
