"""Load and validate a character spec against specs/schema.json (pure Python)."""
import json
import os
import re

SCHEMA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'specs', 'schema.json')
TYPES = {'object': dict, 'array': list, 'string': str, 'number': (int, float), 'integer': int, 'boolean': bool}


def load(path):
    """Return the spec dict, raising ValueError with every schema error."""
    with open(path) as f:
        spec = json.load(f)
    with open(SCHEMA_PATH) as f:
        schema = json.load(f)
    errors = validate(spec, schema, schema)
    if errors:
        raise ValueError(f'{path}: {len(errors)} schema errors\n' + '\n'.join(errors))
    return spec


def validate(value, sch, root, path='$'):
    """Return error strings for the JSON-Schema subset schema.json uses."""
    if '$ref' in sch:
        sch = root['$defs'][sch['$ref'].rsplit('/', 1)[1]]
    t = sch.get('type')
    if t and (not isinstance(value, TYPES[t]) or (t in ('number', 'integer') and isinstance(value, bool))):
        return [f'{path}: expected {t}']
    errs = []
    if 'enum' in sch and value not in sch['enum']:
        errs.append(f'{path}: {value!r} not in {sch["enum"]}')
    if 'pattern' in sch and not re.fullmatch(sch['pattern'], value):
        errs.append(f'{path}: {value!r} does not match {sch["pattern"]}')
    if 'minimum' in sch and value < sch['minimum']:
        errs.append(f'{path}: {value} < {sch["minimum"]}')
    if 'maximum' in sch and value > sch['maximum']:
        errs.append(f'{path}: {value} > {sch["maximum"]}')
    if t == 'object':
        errs += [f'{path}.{k}: required' for k in sch.get('required', []) if k not in value]
        props, extra = sch.get('properties', {}), sch.get('additionalProperties', True)
        for k, v in value.items():
            if k in props:
                errs += validate(v, props[k], root, f'{path}.{k}')
            elif extra is False:
                errs.append(f'{path}.{k}: unknown key')
            elif isinstance(extra, dict):
                errs += validate(v, extra, root, f'{path}.{k}')
    if t == 'array':
        if len(value) < sch.get('minItems', 0):
            errs.append(f'{path}: fewer than {sch["minItems"]} items')
        for i, v in enumerate(value):
            errs += validate(v, sch.get('items', {}), root, f'{path}[{i}]')
    return errs
