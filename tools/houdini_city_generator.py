"""Procedural city generator network builder for Houdini.

Usage in Houdini Python shell:

    import sys
    sys.path.append('/path/to/repo/tools')
    import houdini_city_generator as city
    city.build_city_generator()
"""

from __future__ import annotations


def _set_display_and_render(node):
    node.setDisplayFlag(True)
    node.setRenderFlag(True)


def build_city_generator(parent=None, name: str = "city_generator"):
    """Create a configurable city generator node network.

    Args:
        parent: Optional Houdini parent network. Defaults to /obj.
        name: Name for created Geometry object.

    Returns:
        The created Geometry node.
    """

    import hou

    obj = parent or hou.node("/obj")
    if obj is None:
        raise RuntimeError("Could not find /obj context")

    geo = obj.createNode("geo", node_name=name)

    for child in geo.children():
        child.destroy()

    grid = geo.createNode("grid", "city_area")
    grid.parm("sizex").set(50)
    grid.parm("sizey").set(50)
    grid.parm("rows").set(120)
    grid.parm("cols").set(120)

    scatter = geo.createNode("scatter", "building_points")
    scatter.setInput(0, grid)
    scatter.parm("npts").set(1800)
    scatter.parm("relaxpoints").set(1)

    wrangle = geo.createNode("attribwrangle", "building_attributes")
    wrangle.setInput(0, scatter)
    wrangle.parm("snippet").set(
        """
float n = noise(@P * chf("freq"));
float h = fit(n, 0.0, 1.0, chf("min_h"), chf("max_h"));
float footprint = fit(rand(@ptnum*19.17), 0.0, 1.0, chf("min_f"), chf("max_f"));
v@scale = set(footprint, h, footprint);
@Cd = lerp(set(0.30,0.36,0.45), set(0.85,0.78,0.65), clamp(h/chf("max_h"),0.0,1.0));
""".strip()
    )
    wrangle.addSpareParmTuple(hou.FloatParmTemplate("freq", "Freq", 1, default_value=(0.075,)))
    wrangle.addSpareParmTuple(hou.FloatParmTemplate("min_h", "Min Height", 1, default_value=(2.0,)))
    wrangle.addSpareParmTuple(hou.FloatParmTemplate("max_h", "Max Height", 1, default_value=(28.0,)))
    wrangle.addSpareParmTuple(hou.FloatParmTemplate("min_f", "Min Footprint", 1, default_value=(0.4,)))
    wrangle.addSpareParmTuple(hou.FloatParmTemplate("max_f", "Max Footprint", 1, default_value=(1.8,)))

    box = geo.createNode("box", "building_proto")
    box.parm("sizex").set(1)
    box.parm("sizey").set(1)
    box.parm("sizez").set(1)
    box.parm("ty").set(0.5)

    copy = geo.createNode("copytopoints", "copy_buildings")
    copy.setInput(0, box)
    copy.setInput(1, wrangle)
    copy.parm("doattrtrans").set(1)

    fuse = geo.createNode("fuse", "cleanup")
    fuse.setInput(0, copy)
    fuse.parm("dist").set(0.001)

    out = geo.createNode("null", "OUT_CITY")
    out.setInput(0, fuse)
    _set_display_and_render(out)

    geo.layoutChildren()
    return geo


if __name__ == "__main__":
    print("Run this module inside Houdini's Python environment.")
