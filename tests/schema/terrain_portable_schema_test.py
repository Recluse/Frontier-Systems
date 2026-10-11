"""Portable terrain schemas against real fixed-tick fixtures; local-only references."""
from copy import deepcopy
from pathlib import Path
import json

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
paths = list((ROOT / "docs/schema").glob("*.schema.json"))
schemas = [json.loads(path.read_text(encoding="utf-8-sig")) for path in paths]
registry = Registry().with_resources(
    [(schema["$id"], Resource.from_contents(schema)) for schema in schemas if "$id" in schema]
    + [(path.name, Resource.from_contents(schema)) for path, schema in zip(paths, schemas)]
)
selected = [
    "terrain-system:v3", "terrain-materialize-command:v1",
    "terrain-portable-receipt:v1", "world-snapshot:v1", "construction-coverage:v2",
]
validators = {}
for suffix in selected:
    identifier = "urn:frontier-systems:schema:" + suffix
    schema = next(schema for schema in schemas if schema.get("$id") == identifier)
    Draft202012Validator.check_schema(schema)
    validators[suffix] = Draft202012Validator(schema, registry=registry)
validators["construction-coverage:v2"].validate(json.loads((ROOT / "data/production/construction-coverage.v2.json").read_text()))
fixture = json.loads((ROOT / "var/terrain-portable-fixture.json").read_text())
validators["world-snapshot:v1"].validate(fixture)
terrain = fixture["systems"]["terrain"]
validators["terrain-system:v3"].validate(terrain)
for transfer_id, association in terrain["portable"].items():
    command = {
        "schema_version": 1, "request_number": association["request_number"],
        "payload": {"transfer_id": transfer_id, "expected_inventory_revision": association["expected_inventory_revision"]},
    }
    validators["terrain-materialize-command:v1"].validate(command)
    receipt = {
        "schema_version": 1, "owner_id": terrain["owner"]["owner_id"],
        "transfer_id": transfer_id, "item_id": association["item_id"],
        **terrain["owner"]["transfers"][transfer_id],
    }
    validators["terrain-portable-receipt:v1"].validate(receipt)
legacy = deepcopy(fixture)
legacy["systems"]["terrain"]["schema_version"] = 1
legacy["systems"]["terrain"].pop("portable")
# Shape-only legacy compatibility. Domain validation independently rejects lost payload links.
validators["world-snapshot:v1"].validate(legacy)


def rejects(suffix, record):
    assert not validators[suffix].is_valid(record), "Invalid shape was accepted"


for field, value in (("transfer_id", "foreign"), ("expected_inventory_revision", -1), ("expected_inventory_revision", 1.5)):
    invalid = deepcopy(command)
    invalid["payload"][field] = value
    rejects("terrain-materialize-command:v1", invalid)
invalid = deepcopy(command)
invalid["payload"]["mass_milligrams"] = 1
rejects("terrain-materialize-command:v1", invalid)
invalid = deepcopy(command)
invalid["request_number"] = 129
rejects("terrain-materialize-command:v1", invalid)
invalid = deepcopy(terrain)
invalid["portable"].pop(next(iter(invalid["portable"])))
invalid["schema_version"] = 1
rejects("terrain-system:v3", invalid)
invalid = deepcopy(terrain)
invalid["portable"] = {f"terrain-transfer-{index}": deepcopy(association) for index in range(1, 130)}
rejects("terrain-system:v3", invalid)
invalid = deepcopy(receipt)
invalid["parcels"]["terrain.dirt.source.generation"] = 0
rejects("terrain-portable-receipt:v1", invalid)
print("Portable terrain: five metaschemas, real world/intent/receipt fixtures, legacy shape and eight invalid shapes passed.")
