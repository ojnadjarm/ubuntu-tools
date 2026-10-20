"""Builds a textured subdivided Suzanne in an empty scene and exports it as glTF binary to argv after '--'."""
import sys
import bpy

out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_monkey_add()
obj = bpy.context.active_object
obj.name = "Demo"
mod = obj.modifiers.new("sub", "SUBSURF")
mod.levels = 3
bpy.ops.object.modifier_apply(modifier="sub")
bpy.ops.object.shade_smooth()
img = bpy.data.images.new("checker", 512, 512, alpha=False)
img.generated_type = "COLOR_GRID"
img.pack()
mat = bpy.data.materials.new("DemoMat")
mat.use_nodes = True
tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = img
bsdf = mat.node_tree.nodes["Principled BSDF"]
mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
obj.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="AUTO")
print("ASSET blender tris=%d" % sum(len(p.vertices) - 2 for p in obj.data.polygons))
