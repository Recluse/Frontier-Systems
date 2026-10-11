"""Check terrain bridge shapes using fixtures emitted by the real runtime suite.

Development prerequisite: jsonschema==4.23.0; resolution is local-only.
"""
from copy import deepcopy
from pathlib import Path
import json

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
paths = list((ROOT / "docs/schema").glob("*.schema.json"))
schemas = [json.loads(path.read_text(encoding="utf-8-sig")) for path in paths]
resources = [(schema["$id"], Resource.from_contents(schema)) for schema in schemas if "$id" in schema]
resources.extend((path.name, Resource.from_contents(schema)) for path, schema in zip(paths, schemas))
registry = Registry().with_resources(resources)
selected = {
    schema["$id"]: schema for schema in schemas
    if schema.get("$id") in (
        "urn:frontier-systems:schema:terrain-command:v1",
        "urn:frontier-systems:schema:terrain-system:v3",
        "urn:frontier-systems:schema:world-snapshot:v1",
    )
}
validators = {}
for identifier, schema in selected.items():
    Draft202012Validator.check_schema(schema)
    validators[identifier] = Draft202012Validator(schema, registry=registry)
fixture = json.loads((ROOT / "var/terrain-runtime-fixture.json").read_text(encoding="utf-8"))
world_validator = validators["urn:frontier-systems:schema:world-snapshot:v1"]
world_validator.validate(fixture)
terrain = fixture["systems"]["terrain"]
terrain_validator = validators["urn:frontier-systems:schema:terrain-system:v3"]
terrain_validator.validate(terrain)
command_validator = validators["urn:frontier-systems:schema:terrain-command:v1"]
for mapping in terrain["requests"]:
    command_validator.validate({"schema_version": 1, "request_number": mapping["request_number"], **mapping["intent"]})
legacy = deepcopy(fixture)
del legacy["systems"]["terrain"]
world_validator.validate(legacy)


def rejects(validator, record):
    assert not validator.is_valid(record), "Invalid fixture shape was accepted"


for field, value in (("amount_milligrams", 1000001), ("amount_milligrams", 0), ("amount_milligrams", 1.5), ("expected_tool_revision", -1), ("cell_id", "foreign.cell")):
    invalid = {"schema_version": 1, "request_number": 1, **deepcopy(terrain["requests"][-1]["intent"])}
    invalid["payload"][field] = value
    rejects(command_validator, invalid)
invalid = deepcopy(terrain)
invalid["positions"]["terrain.dirt.source"][0] += 1
rejects(terrain_validator, invalid)
invalid = deepcopy(terrain)
invalid["requests"] *= 2
rejects(terrain_validator, invalid)
invalid = deepcopy(terrain)
invalid["principals"] = {f"principal-{index}": 1 for index in range(17)}
rejects(terrain_validator, invalid)
invalid = {"schema_version": 1, "request_number": 1, **deepcopy(terrain["requests"][-1]["intent"])}
invalid["payload"]["principal_id"] = "client-supplied"
rejects(command_validator, invalid)
print("Terrain command/system and world schemas passed real runtime/checkpoint fixtures, legacy envelope and nine invalid shapes.")

