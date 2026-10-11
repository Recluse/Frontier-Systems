"""Validate the real cooperative projection/journal with a local-only registry."""
from copy import deepcopy
from pathlib import Path
import json
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
paths = list((ROOT / "docs/schema").glob("*.schema.json"))
schemas = [json.loads(path.read_text(encoding="utf-8-sig")) for path in paths]
registry = Registry().with_resources(
    (schema["$id"], Resource.from_contents(schema))
    for schema in schemas if "$id" in schema
)
selected = [schema for schema in schemas if schema.get("$id") in (
    "urn:frontier-systems:schema:terrain-observation:v1",
    "urn:frontier-systems:schema:terrain-client-intent:v1",
)]
validators = {}
for schema in selected:
    Draft202012Validator.check_schema(schema)
    validators[schema["$id"]] = Draft202012Validator(schema, registry=registry)
fixture = json.loads((ROOT / "var/terrain-controls-fixture.json").read_text(encoding="utf-8"))
observation = validators["urn:frontier-systems:schema:terrain-observation:v1"]
intent = validators["urn:frontier-systems:schema:terrain-client-intent:v1"]
observation.validate(fixture["observation"])
intent.validate(fixture["intent"])
bad = []
value = deepcopy(fixture["observation"])
value["cells"]["terrain.dirt.source"]["position_millimetres"][0] = 1
bad.append((observation, value))
value = deepcopy(fixture["observation"])
value["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] = 2000001
bad.append((observation, value))
value = deepcopy(fixture["observation"])
value["next_request_number"] = 1.5
bad.append((observation, value))
value = deepcopy(fixture["observation"])
value["cells"]["terrain.dirt.source"]["work_message"] = "x" * 513
bad.append((observation, value))
value = deepcopy(fixture["intent"])
value["principal_id"] = "forged"
bad.append((intent, value))
value = deepcopy(fixture["intent"])
value["payload"]["owner_sequence"] = 1
bad.append((intent, value))
value = deepcopy(fixture["intent"])
value["payload"]["amount_milligrams"] = 1000001
bad.append((intent, value))
value = deepcopy(fixture["intent"])
value["request_number"] = 0
bad.append((intent, value))
for validator, value in bad:
    assert list(validator.iter_errors(value)), "Invalid shape unexpectedly passed"
print("Terrain controls schema checks: two metaschemas, actual projection/journal and eight invalid shapes passed.")
