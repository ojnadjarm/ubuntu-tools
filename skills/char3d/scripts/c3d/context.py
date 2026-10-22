"""Build state shared by the stages and persisted as <out>/build.json between processes."""
import json
import os
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path


@dataclass
class Context:
    spec: dict
    out: Path
    draft: bool = False
    landmarks: dict = field(default_factory=dict)
    parts: dict = field(default_factory=dict)
    bones: dict = field(default_factory=dict)
    controls: dict = field(default_factory=dict)
    face: dict = field(default_factory=dict)
    clips: dict = field(default_factory=dict)
    textures: dict = field(default_factory=dict)
    lods: dict = field(default_factory=dict)
    renders: dict = field(default_factory=dict)
    files: dict = field(default_factory=dict)
    stages: dict = field(default_factory=dict)
    options: dict = field(default_factory=dict)

    @property
    def id(self):
        return self.spec['id']

    @property
    def blend(self):
        return self.out / f'{self.id}.blend'

    def add_part(self, part_id, obj_name, stage, material=None, attach=None):
        """Register a scene object under a spec id so later stages find it by role, not by name."""
        self.parts[part_id] = {'object': obj_name, 'stage': stage, 'material': material, 'attach': attach}

    def record(self, stage, seconds, metrics):
        self.stages[stage] = {'seconds': round(seconds, 4), **(metrics or {})}

    def save(self, name='build.json'):
        self.out.mkdir(parents=True, exist_ok=True)
        data = asdict(self)
        data['out'] = str(self.out)
        data['saved'] = time.strftime('%Y-%m-%dT%H:%M:%S')
        tmp = self.out / f'.{name}.tmp'
        tmp.write_text(json.dumps(data, indent=1))
        os.replace(tmp, self.out / name)

    @classmethod
    def load(cls, out, spec, draft=False):
        """Reopen the state a previous build wrote; the spec passed in wins over the stored one."""
        data = json.loads((Path(out) / 'build.json').read_text())
        data.pop('saved', None)
        data.update(spec=spec, out=Path(out), draft=draft)
        return cls(**data)
