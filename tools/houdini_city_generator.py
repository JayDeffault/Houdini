"""Procedural road & intersection generator for Houdini.

Usage in Houdini Python shell:

    import sys
    sys.path.append('/path/to/repo/tools')
    import houdini_city_generator as gen
    gen.build_road_generator()
"""

from __future__ import annotations


def _set_display_and_render(node):
    node.setDisplayFlag(True)
    node.setRenderFlag(True)


def _set_parm(node, parm_name: str, value):
    parm = node.parm(parm_name)
    if parm is not None:
        parm.set(value)


def _add_controls(geo):
    import hou

    controls = [
        hou.FloatParmTemplate("city_size", "City Size", 1, default_value=(120.0,)),
        hou.IntParmTemplate("street_count", "Street Count", 1, default_value=(12,), min=2, min_is_strict=False),
        hou.IntParmTemplate("avenue_count", "Avenue Count", 1, default_value=(10,), min=2, min_is_strict=False),
        hou.FloatParmTemplate("road_width", "Road Width", 1, default_value=(2.8,)),
        hou.FloatParmTemplate("intersection_scale", "Intersection Scale", 1, default_value=(1.35,)),
    ]

    for template in controls:
        geo.addSpareParmTuple(template)


def build_road_generator(parent=None, name: str = "road_intersection_generator"):
    """Create a configurable road/intersection generator network in /obj."""

    import hou

    obj = parent or hou.node("/obj")
    if obj is None:
        raise RuntimeError("Could not find /obj context")

    geo = obj.createNode("geo", node_name=name)

    for child in geo.children():
        child.destroy()

    _add_controls(geo)

    # Template points along Z: where horizontal streets will be placed.
    z_points = geo.createNode("line", "z_street_offsets")
    _set_parm(z_points, "dirx", 0)
    _set_parm(z_points, "diry", 0)
    _set_parm(z_points, "dirz", 1)
    _set_parm(z_points, "dist", 1)
    _set_parm(z_points, "originx", 0)
    _set_parm(z_points, "originy", 0)
    _set_parm(z_points, "originz", 0)
    _set_parm(z_points, "points", 12)
    if z_points.parm("points") is not None:
        z_points.parm("points").setExpression('ch("../street_count")')
    if z_points.parm("length") is not None:
        z_points.parm("length").setExpression('ch("../city_size")')

    # Base horizontal road centerline.
    x_road = geo.createNode("line", "x_road_centerline")
    _set_parm(x_road, "dirx", 1)
    _set_parm(x_road, "diry", 0)
    _set_parm(x_road, "dirz", 0)
    _set_parm(x_road, "dist", 1)
    if x_road.parm("length") is not None:
        x_road.parm("length").setExpression('ch("../city_size")')

    copy_x = geo.createNode("copytopoints", "copy_x_roads")
    copy_x.setInput(0, x_road)
    copy_x.setInput(1, z_points)

    # Template points along X: where vertical avenues will be placed.
    x_points = geo.createNode("line", "x_avenue_offsets")
    _set_parm(x_points, "dirx", 1)
    _set_parm(x_points, "diry", 0)
    _set_parm(x_points, "dirz", 0)
    _set_parm(x_points, "dist", 1)
    if x_points.parm("points") is not None:
        x_points.parm("points").setExpression('ch("../avenue_count")')
    if x_points.parm("length") is not None:
        x_points.parm("length").setExpression('ch("../city_size")')

    z_road = geo.createNode("line", "z_road_centerline")
    _set_parm(z_road, "dirx", 0)
    _set_parm(z_road, "diry", 0)
    _set_parm(z_road, "dirz", 1)
    _set_parm(z_road, "dist", 1)
    if z_road.parm("length") is not None:
        z_road.parm("length").setExpression('ch("../city_size")')

    copy_z = geo.createNode("copytopoints", "copy_z_roads")
    copy_z.setInput(0, z_road)
    copy_z.setInput(1, x_points)

    merge_centerlines = geo.createNode("merge", "merge_centerlines")
    merge_centerlines.setInput(0, copy_x)
    merge_centerlines.setInput(1, copy_z)

    fuse_centerlines = geo.createNode("fuse", "fuse_centerlines")
    fuse_centerlines.setInput(0, merge_centerlines)
    _set_parm(fuse_centerlines, "dist", 0.001)

    roads_surface = geo.createNode("polyexpand2d", "roads_surface")
    roads_surface.setInput(0, fuse_centerlines)
    if roads_surface.parm("offset") is not None:
        roads_surface.parm("offset").setExpression('ch("../road_width")*0.5')

    # Explicit intersection pads for cleaner junctions.
    intersection_pts = geo.createNode("add", "intersection_point")
    _set_parm(intersection_pts, "pt0x", 0)
    _set_parm(intersection_pts, "pt0y", 0)
    _set_parm(intersection_pts, "pt0z", 0)

    copy_intersections_x = geo.createNode("copytopoints", "copy_intersections_x")
    copy_intersections_x.setInput(0, intersection_pts)
    copy_intersections_x.setInput(1, x_points)

    copy_intersections_grid = geo.createNode("copytopoints", "copy_intersections_grid")
    copy_intersections_grid.setInput(0, copy_intersections_x)
    copy_intersections_grid.setInput(1, z_points)

    circle = geo.createNode("circle", "intersection_pad")
    _set_parm(circle, "type", 1)
    if circle.parm("radx") is not None:
        circle.parm("radx").setExpression('ch("../road_width")*0.5*ch("../intersection_scale")')
    if circle.parm("rady") is not None:
        circle.parm("rady").setExpression('ch("../road_width")*0.5*ch("../intersection_scale")')

    copy_pads = geo.createNode("copytopoints", "copy_intersection_pads")
    copy_pads.setInput(0, circle)
    copy_pads.setInput(1, copy_intersections_grid)

    merge_surface = geo.createNode("merge", "merge_roads_and_intersections")
    merge_surface.setInput(0, roads_surface)
    merge_surface.setInput(1, copy_pads)

    clean = geo.createNode("fuse", "clean_surface")
    clean.setInput(0, merge_surface)
    _set_parm(clean, "dist", 0.002)

    color = geo.createNode("color", "road_color")
    color.setInput(0, clean)
    _set_parm(color, "colorr", 0.11)
    _set_parm(color, "colorg", 0.12)
    _set_parm(color, "colorb", 0.13)

    out = geo.createNode("null", "OUT_ROADS")
    out.setInput(0, color)
    _set_display_and_render(out)

    geo.layoutChildren()
    return geo


if __name__ == "__main__":
    print("Run inside Houdini and call build_road_generator().")
