"""Real v3 lifecycle, holder journal, and legacy v2; local-only schema resolution."""
from copy import deepcopy
from pathlib import Path
import json
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
paths = list((ROOT / "docs/schema").glob("*.schema.json"))
schemas = [json.loads(p.read_text(encoding="utf-8-sig")) for p in paths]
registry = Registry().with_resources([(s["$id"], Resource.from_contents(s)) for s in schemas if "$id" in s] + [(p.name, Resource.from_contents(s)) for p, s in zip(paths, schemas)])
validators = {}
for name in ("terrain-system:v2", "terrain-system:v3", "terrain-observation:v3", "terrain-client-intent:v3", "terrain-return-command:v1", "terrain-return-receipt:v1", "terrain-portable-receipt:v1", "world-snapshot:v1"):
    schema = next(s for s in schemas if s.get("$id") == "urn:frontier-systems:schema:" + name)
    Draft202012Validator.check_schema(schema)
    validators[name] = Draft202012Validator(schema, registry=registry)
fixture = json.loads((ROOT / "var/terrain-return-fixture.json").read_text())
for stage in ("active", "transferred", "returned", "partial", "filled", "expired", "remainder_claim", "remainder_return"):
    validators["world-snapshot:v1"].validate(fixture[stage])
    validators["terrain-system:v3"].validate(fixture[stage]["systems"]["terrain"])
validators["terrain-system:v2"].validate(fixture["legacy"]["systems"]["terrain"])
validators["terrain-portable-receipt:v1"].validate(fixture["claim_receipt"])
validators["terrain-return-receipt:v1"].validate(fixture["return_receipt"])
validators["terrain-observation:v3"].validate(fixture["observation"])
client = json.loads((ROOT / "var/terrain-return-client-fixture.json").read_text())
validators["terrain-observation:v3"].validate(client["observation"])
intent = client["intent"]
validators["terrain-client-intent:v3"].validate(intent)
command = {"schema_version": 1, "request_number": intent["request_number"], "payload": intent["payload"]}
validators["terrain-return-command:v1"].validate(command)
bad = []
for field in ("mass_milligrams", "material_id", "principal_id", "parcels", "transfer_id", "destination_container_id"):
    value = deepcopy(intent)
    value["payload"][field] = "forged"
    bad.append(("terrain-client-intent:v3", value))
for field, value in (("item_id", "terrain-item-01"), ("item_id", "foreign"), ("expected_inventory_revision", -1), ("expected_inventory_revision", 1.5)):
    invalid = deepcopy(command)
    invalid["payload"][field] = value
    bad.append(("terrain-return-command:v1", invalid))
for field, value in (("request_number", 0), ("request_number", 129), ("schema_version", 2), ("operation", "consume"), ("operation", "materialize")):
    invalid = deepcopy(intent)
    invalid[field] = value
    bad.append(("terrain-client-intent:v3", invalid))
for field, value in (("next_return_request_number", 129), ("return_ready", 1), ("return_message", "x" * 513)):
    invalid = deepcopy(client["observation"])
    invalid[field] = value
    bad.append(("terrain-observation:v3", invalid))
invalid = deepcopy(fixture["filled"]["systems"]["terrain"])
invalid["portable"]["terrain-transfer-1"].pop("receipt")
bad.append(("terrain-system:v3", invalid))
invalid = deepcopy(fixture["return_receipt"])
invalid["owner_sequence"] = -1
bad.append(("terrain-return-receipt:v1", invalid))
for name, value in bad:
    assert not validators[name].is_valid(value), f"Forged shape unexpectedly passed: {name}"
print(f"Terrain return: eight metaschemas, all lifecycle/legacy/remainder fixtures, original receipts, real holder journal, and {len(bad)} malformed shapes passed.")
