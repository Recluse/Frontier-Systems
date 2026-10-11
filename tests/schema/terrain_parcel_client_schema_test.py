"""Real scoped projection/journal, legacy compatibility and forged claim shapes."""
from copy import deepcopy
from pathlib import Path
import json
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
schemas = [json.loads(p.read_text(encoding="utf-8-sig")) for p in (ROOT / "docs/schema").glob("*.schema.json")]
registry = Registry().with_resources((s["$id"], Resource.from_contents(s)) for s in schemas if "$id" in s)
validators = {}
for name in ("terrain-observation:v1", "terrain-observation:v3", "terrain-client-intent:v1", "terrain-client-intent:v2", "terrain-materialize-command:v1"):
    schema = next(s for s in schemas if s.get("$id") == "urn:frontier-systems:schema:" + name)
    Draft202012Validator.check_schema(schema)
    validators[name] = Draft202012Validator(schema, registry=registry)
fixture = json.loads((ROOT / "var/terrain-parcel-client-fixture.json").read_text(encoding="utf-8"))
view = fixture["observation"]
intent = fixture["intent"]
validators["terrain-observation:v3"].validate(view)
validators["terrain-client-intent:v2"].validate(intent)
validators["terrain-materialize-command:v1"].validate({"schema_version": 1, "request_number": intent["request_number"], "payload": intent["payload"]})
legacy = deepcopy(view)
legacy["schema_version"] = 1
for field in ("next_materialize_request_number", "materialize_sequence_exhausted", "materialize_ready", "materialize_message", "returnable_parcels", "fill_only_transfers", "next_return_request_number", "return_sequence_exhausted", "return_ready", "return_message"):
    del legacy[field]
validators["terrain-observation:v1"].validate(legacy)
work = json.loads((ROOT / "var/terrain-controls-fixture.json").read_text(encoding="utf-8"))["intent"]
validators["terrain-client-intent:v1"].validate(work)
work["schema_version"] = 2
validators["terrain-client-intent:v2"].validate(work)
bad = []
for field in ("mass_milligrams", "definition_id", "material_id", "parcels", "principal_id", "destination_container_id"):
    value = deepcopy(intent)
    value["payload"][field] = "forged"
    bad.append((validators["terrain-client-intent:v2"], value))
for field, replacement in (("request_number", 0), ("request_number", 129), ("request_number", 1.5), ("schema_version", 1), ("operation", "consume")):
    value = deepcopy(intent)
    value[field] = replacement
    bad.append((validators["terrain-client-intent:v2"], value))
for field, replacement in (("transfer_id", "terrain-transfer-01"), ("transfer_id", "foreign"), ("expected_inventory_revision", -1), ("expected_inventory_revision", 1.5)):
    value = deepcopy(intent)
    value["payload"][field] = replacement
    bad.append((validators["terrain-client-intent:v2"], value))
for field, replacement in (("next_materialize_request_number", 129), ("next_materialize_request_number", 1.5), ("materialize_message", "x" * 513), ("materialize_ready", 1), ("portable", {})):
    value = deepcopy(view)
    value[field] = replacement
    bad.append((validators["terrain-observation:v3"], value))
for validator, value in bad:
    assert list(validator.iter_errors(value)), "Forged claim shape unexpectedly passed"
print(f"Terrain parcel client schemas: five metaschemas, real claims/journals, explicit legacy compatibility and {len(bad)} malformed shapes passed.")