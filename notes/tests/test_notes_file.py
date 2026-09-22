"""notes-file.py on a fixture vault; the real ~/obsidian-vault is never touched."""
import importlib.util
import io
import json
import os
import time

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("notes_file", os.path.join(HERE, "..", "notes-file.py"))
nf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nf)

IDEA = "audio notes/ideas/eye-brains.md"


@pytest.fixture
def vault(tmp_path, monkeypatch):
    v = tmp_path / "vault"
    (v / "audio notes" / "ideas").mkdir(parents=True)
    (v / ".obsidian").mkdir()
    (v / ".obsidian" / "workspace.md").write_text("# nope\n")
    monkeypatch.setenv("NOTES_VAULT_DIR", str(v))
    monkeypatch.setenv("NOTES_FOLDER", "audio notes")
    monkeypatch.setenv("NOTES_HOME", str(tmp_path / "home"))
    return v


def today():
    return time.strftime("%Y-%m-%d")


def daily(vault):
    return vault / "audio notes" / f"{today()}.md"


def apply(tmp_path, plan):
    p = tmp_path / f"plan-{time.time_ns()}.json"
    p.write_text(json.dumps(plan))
    return nf.main(["apply", str(p)])


def snapshot(vault):
    return {str(p.relative_to(vault)): p.read_bytes() for p in vault.rglob("*") if p.is_file()}


def logged(tmp_path):
    return (tmp_path / "home" / "logs" / "notes-file.log").read_text()


def test_raw_creates_daily_then_appends(vault):
    assert nf.main(["raw", "first thought"]) == 0
    text = daily(vault).read_text()
    assert text.startswith(f"# {today()}\n\n## Raw\n")
    assert "## Refined\n" in text
    lines = [l for l in text.splitlines() if l.startswith("- ")]
    assert len(lines) == 1 and lines[0].endswith(" — first thought")
    assert nf.main(["raw", "second"]) == 0
    text = daily(vault).read_text()
    raw, refined = text.split("## Refined")
    assert raw.count("- ") == 2 and "second" in raw and refined.strip() == ""
    assert sorted(os.listdir(vault / "audio notes")) == [f"{today()}.md", "ideas"]


def test_apply_append_create_refined(vault, tmp_path):
    idea = vault / IDEA
    idea.write_text("---\ntags: [dark-eye]\n---\n# Eye brains\n\n## Switch UX\n\nOld text.\n\n## Colours\n\nGreen is the eye's.\n")
    before = idea.read_text()
    plan = {"actions": [
        {"op": "append", "file": IDEA, "heading": "Switch UX", "text": "Chips switch the brain.", "sure": True},
        {"op": "append", "file": IDEA, "heading": "Voice", "text": "Say the name.", "sure": True},
        {"op": "create", "file": "audio notes/ideas/kitchen-lamp.md", "title": "Kitchen lamp", "tags": ["home"], "text": "Warm bulb.", "sure": False},
        {"op": "create", "file": IDEA, "text": "Created again.", "sure": True}],
        "refined": [{"at": "22:41", "file": IDEA, "heading": "Switch UX", "gist": "Chips switch."},
                    {"at": "22:42", "file": "audio notes/ideas/kitchen-lamp.md", "gist": "Lamp."}]}
    assert apply(tmp_path, plan) == 0
    after = idea.read_text()
    assert after.startswith("---\ntags: [dark-eye]\n---\n# Eye brains\n\n## Switch UX\n\nOld text.\n\nChips switch the brain.\n\n## Colours\n\nGreen is the eye's.\n\n## Voice\n\nSay the name.\n\nCreated again.\n")
    assert after.replace("\nChips switch the brain.\n", "").replace("\n## Voice\n\nSay the name.\n\nCreated again.\n", "") == before
    lamp = (vault / "audio notes/ideas/kitchen-lamp.md").read_text()
    assert lamp == "---\ntags: [home]\n---\n# Kitchen lamp\n\nWarm bulb.\n"
    refined = daily(vault).read_text().split("## Refined\n")[1]
    assert "- 22:41 → [[audio notes/ideas/eye-brains#Switch UX]] Chips switch.\n" in refined
    assert "- 22:42 → [[audio notes/ideas/kitchen-lamp]] Lamp. (?)\n" in refined
    assert "apply ok" in logged(tmp_path)


def test_tags_union(vault, tmp_path):
    idea = vault / IDEA
    idea.write_text("---\ntags: [a]\n---\n# T\n\nbody\n")
    assert apply(tmp_path, {"actions": [{"op": "append", "file": IDEA, "text": "x", "tags": ["a", "b"]}]}) == 0
    assert idea.read_text().startswith("---\ntags: [a, b]\n---\n")
    assert apply(tmp_path, {"actions": [{"op": "append", "file": IDEA, "text": "y", "tags": ["b"]}]}) == 0
    assert idea.read_text().startswith("---\ntags: [a, b]\n---\n")


@pytest.mark.parametrize("action", [
    {"op": "append", "file": "../escape.md", "text": "x"},
    {"op": "append", "file": "/tmp/abs.md", "text": "x"},
    {"op": "append", "file": "out/leak.md", "text": "x"},
    {"op": "replace", "file": IDEA, "text": "x"},
    {"op": "append", "file": IDEA, "text": "x" * 4001},
    {"op": "append", "file": "audio notes/ideas/not-markdown.txt", "text": "x"},
    {"op": "append", "file": "audio notes/.md", "text": "x"},
    {"op": "append", "file": IDEA, "heading": "## ", "text": "x"},
])
def test_refused_actions(vault, tmp_path, action):
    outside = tmp_path / "outside"
    outside.mkdir()
    os.symlink(outside, vault / "out")
    (vault / IDEA).write_text("# T\n")
    before = snapshot(vault)
    assert apply(tmp_path, {"actions": [action]}) == 1
    assert snapshot(vault) == before and not os.listdir(outside)
    assert "apply refused" in logged(tmp_path)


def test_apply_reads_stdin(vault, monkeypatch):
    plan = {"actions": [{"op": "create", "file": IDEA, "title": "Eye brains", "text": "From stdin."}]}
    monkeypatch.setattr("sys.stdin", io.StringIO(json.dumps(plan)))
    assert nf.main(["apply", "-"]) == 0
    assert (vault / IDEA).read_text().endswith("# Eye brains\n\nFrom stdin.\n")


def test_heading_marks_stripped(vault, tmp_path):
    idea = vault / IDEA
    idea.write_text("# T\n\n## Switch UX\n\nOld.\n\n## Other\n\nKeep.\n")
    plan = {"actions": [{"op": "append", "file": IDEA, "heading": "## Switch UX", "text": "New."}],
            "refined": [{"at": "10:00", "file": IDEA, "heading": "# Switch UX", "gist": "g"}]}
    assert apply(tmp_path, plan) == 0
    assert idea.read_text() == "# T\n\n## Switch UX\n\nOld.\n\nNew.\n\n## Other\n\nKeep.\n"
    assert "[[audio notes/ideas/eye-brains#Switch UX]] g\n" in daily(vault).read_text()


def test_no_vault_refuses_and_creates_nothing(tmp_path, monkeypatch):
    missing = tmp_path / "notes"
    monkeypatch.setenv("NOTES_VAULT_DIR", str(missing))
    monkeypatch.setenv("NOTES_HOME", str(tmp_path / "home"))
    assert nf.main(["raw", "x"]) == 1
    assert apply(tmp_path, {"actions": [{"op": "create", "file": IDEA, "text": "x"}]}) == 1
    assert not missing.exists()
    assert logged(tmp_path).count("refused no vault at") == 2


def test_refused_seventh_action_and_bad_schema(vault, tmp_path):
    before = snapshot(vault)
    seven = [{"op": "append", "file": IDEA, "text": "x"}] * 7
    assert apply(tmp_path, {"actions": seven}) == 1
    assert apply(tmp_path, {"actions": [{"op": "append", "file": IDEA}]}) == 1
    assert apply(tmp_path, {"plan": []}) == 1
    assert snapshot(vault) == before
    assert logged(tmp_path).count("apply refused schema") == 3


def test_shrink_guard_fires_before_rename(vault, tmp_path, monkeypatch):
    idea = vault / IDEA
    idea.write_text("# T\n\nlong body here\n")
    monkeypatch.setattr(nf, "plan_changes", lambda plan: {str(idea): "# T\n"})
    assert apply(tmp_path, {"actions": [{"op": "append", "file": IDEA, "text": "x"}]}) == 1
    assert idea.read_text() == "# T\n\nlong body here\n"
    assert not [n for n in os.listdir(idea.parent) if n.startswith(".notes-file-")]
    assert "apply refused would shrink" in logged(tmp_path)


def test_twenty_one_files_in_an_hour_refused(vault, tmp_path):
    def creates(n, start):
        return {"actions": [{"op": "create", "file": f"audio notes/ideas/i{start + k}.md", "text": "x"} for k in range(n)]}
    for start in (0, 6, 12):
        assert apply(tmp_path, creates(6, start)) == 0
    assert apply(tmp_path, creates(2, 18)) == 0
    assert apply(tmp_path, creates(1, 20)) == 1
    assert not (vault / "audio notes/ideas/i20.md").exists()
    assert "apply refused 21 files inside an hour" in logged(tmp_path)


def test_index(vault, tmp_path, capsys):
    (vault / "a.md").write_text("---\ntags: [x, y]\n---\n# Alpha\n\n## One\ntext one\n## Two\n" + "z" * 300 + "\n")
    (vault / IDEA).write_text("# Eye brains\n\n## Switch UX\nchips\n")
    (vault / "audio notes/ideas/c.md").write_text("---\ntags:\n  - home\n---\n# Gamma\n\nlamp\n")
    daily(vault).write_text("# today\n## Raw\n")
    assert nf.main(["index"]) == 0
    rows = {r["file"]: r for r in map(json.loads, capsys.readouterr().out.splitlines())}
    assert set(rows) == {"a.md", IDEA, "audio notes/ideas/c.md"}
    assert rows["a.md"]["title"] == "Alpha" and rows["a.md"]["tags"] == ["x", "y"]
    assert rows["a.md"]["headings"] == ["One", "Two"] and len(rows["a.md"]["excerpt"]) == 200
    assert rows["audio notes/ideas/c.md"]["tags"] == ["home"]
    assert rows[IDEA]["headings"] == ["Switch UX"] and rows[IDEA]["excerpt"] == "chips"

    cache_path = tmp_path / "home" / "state" / "index.json"
    cache = json.loads(cache_path.read_text())
    cache["a.md"]["title"] = "CACHED"
    cache[IDEA]["title"] = "STALE"
    cache_path.write_text(json.dumps(cache))
    (vault / IDEA).write_text("# Eye brains v2\n\nmore\n")
    assert nf.main(["index"]) == 0
    rows = {r["file"]: r for r in map(json.loads, capsys.readouterr().out.splitlines())}
    assert rows["a.md"]["title"] == "CACHED" and rows[IDEA]["title"] == "Eye brains v2"


def test_index_cap_degrades_oldest_to_titles(vault, tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(nf, "INDEX_MAX_FILES", 3)
    for i in range(5):
        p = vault / f"n{i}.md"
        p.write_text(f"# Note {i}\n\n## H\nbody\n")
        os.utime(p, (1_000_000 + i, 1_000_000 + i))
    assert nf.main(["index"]) == 0
    rows = [json.loads(r) for r in capsys.readouterr().out.splitlines()]
    assert [r["file"] for r in rows] == ["n4.md", "n3.md", "n2.md", "n1.md", "n0.md"]
    assert all("headings" in r for r in rows[:3])
    assert rows[3] == {"file": "n1.md", "title": "Note 1"} and rows[4] == {"file": "n0.md", "title": "Note 0"}
