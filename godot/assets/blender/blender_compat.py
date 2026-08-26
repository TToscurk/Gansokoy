"""Blender API compatibility helpers shared by every exporter in this folder.

Import it the way `make_trees.py` / `make_hieda.py` already import `tree_lib`:

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import blender_compat as BC

Why this exists
---------------
Every exporter used to reach for the shader node by its literal English name:

    mat.node_tree.nodes["Principled BSDF"]
    world.node_tree.nodes["Background"]

That is not a version problem, it is a **locale** problem, which is worse
because it is invisible to whoever authored the script. Newly created nodes are
named in the running Blender's UI language. On the machine this project builds
on, `bpy.data.materials.new(...)` + `use_nodes = True` produces:

    [('原則化 BSDF', 'BSDF_PRINCIPLED'), ('材質輸出', 'OUTPUT_MATERIAL')]

so `nodes.get("Principled BSDF")` returns None and `nodes["Principled BSDF"]`
raises. Every one of these scripts died on its first material. It also means
two people on the same Blender version get different results, and the failure
only appears when someone next regenerates an asset — which in this project can
be months after the script was written.

`node.type` is a stable enum and is not translated. Look up by type.

(Nodes that came from the startup .blend keep their English names, which is why
`scene.world.node_tree.nodes["Background"]` happened to keep working while
`bpy.data.worlds.new(...)` did not. That is luck, not a contract.)
"""
import bpy


def principled(mat):
    """Return the material's Principled BSDF, creating and linking one if absent.

    Looks up by node TYPE ('BSDF_PRINCIPLED'), never by name.
    """
    nt = mat.node_tree
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    node = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) \
        or nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(node.outputs["BSDF"], out.inputs["Surface"])
    return node


def background(world):
    """Return the world's Background node, creating and linking one if absent.

    Looks up by node TYPE ('BACKGROUND'), never by name.
    """
    nt = world.node_tree
    for n in nt.nodes:
        if n.type == "BACKGROUND":
            return n
    node = nt.nodes.new("ShaderNodeBackground")
    out = next((n for n in nt.nodes if n.type == "OUTPUT_WORLD"), None) \
        or nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(node.outputs["Background"], out.inputs["Surface"])
    return node
