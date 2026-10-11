"""Validate real host/client recipe observations and legacy persistence locally."""
from pathlib import Path
import json
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
paths = list((ROOT / "docs/schema").glob("*.schema.json"))
schemas = [json.loads(p.read_text(encoding="utf-8-sig")) for p in paths]
registry = Registry().with_resources([(s["$id"], Resource.from_contents(s)) for s in schemas if "$id" in s] + [(p.name, Resource.from_contents(s)) for p, s in zip(paths, schemas)])
validators = {}
for name in ("production-observation:v7", "production-observation:v8", "production-system:v7"):
    schema = next(s for s in schemas if s.get("$id") == "urn:frontier-systems:schema:" + name)
    Draft202012Validator.check_schema(schema)
    validators[name] = Draft202012Validator(schema, registry=registry)
fixture = json.loads((ROOT / "var/recipe-requirements-fixture.json").read_text())
for key in ("current", "alternate"):
    validators["production-observation:v8"].validate(fixture[key])
    requirements = fixture[key]["recipe_requirements"]
    assert set(requirements) == set(fixture[key]["recipes"])
    assert all(sum(r["inputs"].values()) <= 100000000 for r in requirements.values())
validators["production-observation:v7"].validate(fixture["legacy"])
validators["production-system:v7"].validate(fixture["persistent"])
assert not validators["production-observation:v7"].is_valid(fixture["current"])
assert not validators["production-system:v7"].is_valid(fixture["current"])
assert not validators["production-observation:v8"].is_valid(fixture["legacy"])
schema_rejections = 0
for invalid in fixture["malformed"]:
    if not validators["production-observation:v8"].is_valid(invalid):
        schema_rejections += 1
        continue
    # Dynamic key equality and total input mass are explicit runtime constraints.
    requirements = invalid["recipe_requirements"]
    assert set(requirements) != set(invalid["recipes"]) or any(sum(r["inputs"].values()) > 100000000 for r in requirements.values())
print(f"Recipe schemas: real v8/alternate, legacy v7, persistent v7 and {schema_rejections} schema plus {len(fixture['malformed']) - schema_rejections} semantic rejections passed.")
