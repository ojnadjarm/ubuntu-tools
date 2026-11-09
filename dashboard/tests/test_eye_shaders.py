"""The eye's lid and basis GLSL lives once in gl/glsl.js; every eye shader gets exactly one copy of each."""
import json, os, re, subprocess

GL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "static", "next", "js", "gl")
DEFS = {"lidsAt": r"vec2 lidsAt\(", "basis": r"mat3 basis\(", "lid formula": r"uLid\.x \* pow\(s, 0\.62\)"}


def test_lid_and_basis_glsl_written_once_in_glsl_js():
    found = {}
    for root, _, files in os.walk(GL):
        for f in files:
            if f.endswith(".js"):
                src = open(os.path.join(root, f)).read()
                for name, rx in DEFS.items():
                    n = len(re.findall(rx, src))
                    if n:
                        found.setdefault(name, {})[os.path.relpath(os.path.join(root, f), GL)] = n
    assert found == {name: {"glsl.js": 1} for name in DEFS}


def test_each_eye_shader_has_one_lidsAt_and_one_basis():
    js = ("Promise.all(['swarm', 'oracle'].map((n) => import('./eyes/' + n + '.js')))"
          ".then((m) => console.log(JSON.stringify({ swarm: m[0].default.vs, oracle: m[1].default.fs })))")
    out = subprocess.run(["node", "--input-type=module", "-e", js], cwd=GL, capture_output=True, text=True, check=True)
    for name, src in json.loads(out.stdout).items():
        assert len(re.findall(DEFS["lidsAt"], src)) == 1, name
        assert len(re.findall(DEFS["basis"], src)) == 1, name
