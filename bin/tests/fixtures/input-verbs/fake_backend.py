#!/usr/bin/env python3
"""Recording stand-in for portal_shot.py, ocr_find.py, a11y_tree.py and rd_type.py: logs '<name> <json argv>' to $SHIM_LOG."""
import json, os, sys

name, args = os.path.basename(sys.argv[0]), sys.argv[1:]
with open(os.environ["SHIM_LOG"], "a") as log:
    log.write("%s %s\n" % (name, json.dumps(args)))
fix = os.environ["FAKE_FIXTURES"]

if name == "portal_shot.py":
    from PIL import Image
    w, h = (int(v) for v in os.environ.get("FAKE_SHOT_SIZE", "200x100").split("x"))
    Image.new("RGB", (w, h), os.environ.get("FAKE_SHOT_COLOR", "white")).save(args[0])
elif name == "ocr_find.py":
    shot, q, all_, as_json = args[:4]
    hits = json.load(open(os.path.join(fix, "ocr.json"))).get(q, [])
    hits = hits if all_ == "1" else hits[:1]
    print(json.dumps(hits) if as_json == "1" else "\n".join(hits))
elif name == "a11y_tree.py":
    tree = json.load(open(os.environ.get("FAKE_A11Y_TREE", os.path.join(fix, "a11y-tree.json"))))
    if "--modal-check" in args:
        if tree["modal"]:
            print(tree["modal"])
            sys.exit(0)
        sys.exit(1)
    find = args[args.index("--find") + 1]
    role = args[args.index("--role") + 1] if "--role" in args else None
    for el in tree["elements"]:
        if el["name"] == find and role in (None, el["role"]) and args[0] in el["app"]:
            print(el["click"])
            sys.exit(0)
    sys.exit(1)
