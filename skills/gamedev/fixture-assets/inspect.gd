extends SceneTree
## Loads each res://*.glb, prints triangles and the base-colour texture size per model, then quits.

func _init() -> void:
	for f in DirAccess.get_files_at("res://"):
		if not f.ends_with(".glb"):
			continue
		var scene: PackedScene = load("res://" + f)
		if scene == null:
			print("ASSET import FAIL %s" % f)
			continue
		var root := scene.instantiate()
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = mi.mesh
			var tris := 0
			for s in mesh.get_surface_count():
				tris += mesh.surface_get_array_index_len(s) / 3
			var mat := mesh.surface_get_material(0) as BaseMaterial3D
			var tex := mat.albedo_texture if mat else null
			print("ASSET import OK %s tris=%d texture=%s" % [f, tris, "%dx%d" % [tex.get_width(), tex.get_height()] if tex else "none"])
		root.free()
	quit()
