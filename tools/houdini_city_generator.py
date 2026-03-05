"""Curve-driven procedural road and intersection generator for Houdini.

This module is designed for the workflow where an artist draws input curve
centerlines manually, including intersections. The generator then:

1. Cleans and fuses curve intersections.
2. Splits roads by semantic group (primary/secondary/local/highway).
3. Converts each group to polygon road surfaces with independent width control.
4. Builds explicit intersection pads from high-valence points.
5. Merges and colors final road polygons.

Expected input:
- SOP geometry containing polyline curves.
- Optional primitive string attribute: `road_group`
  (values: primary, secondary, local, highway).

If `road_group` is missing, all roads are treated as `local`.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class RoadGroupDefinition:
    name: str
    label: str
    default_width: float
    color: tuple[float, float, float]


ROAD_GROUPS = (
    RoadGroupDefinition("highway", "Highway Width", 8.0, (0.20, 0.20, 0.22)),
    RoadGroupDefinition("primary", "Primary Width", 6.0, (0.16, 0.16, 0.18)),
    RoadGroupDefinition("secondary", "Secondary Width", 4.5, (0.13, 0.13, 0.15)),
    RoadGroupDefinition("local", "Local Width", 3.0, (0.11, 0.11, 0.13)),
)


class Graph:
    """Minimal helper for SOP node creation/wiring."""

    def __init__(self, geo):
        self.geo = geo
        self.nodes = {}

    def create(self, node_type: str, name: str):
        node = self.geo.createNode(node_type, name)
        self.nodes[name] = node
        return node

    def connect(self, dst: str, idx: int, src: str) -> None:
        self.nodes[dst].setInput(idx, self.nodes[src])

    def parm(self, node_name: str, parm_name: str):
        return self.nodes[node_name].parm(parm_name)

    def set_parm(self, node_name: str, parm_name: str, value) -> None:
        parm = self.parm(node_name, parm_name)
        if parm is not None:
            parm.set(value)

    def set_expr(self, node_name: str, parm_name: str, expr: str) -> None:
        parm = self.parm(node_name, parm_name)
        if parm is not None:
            parm.setExpression(expr)



def _set_display_and_render(node) -> None:
    node.setDisplayFlag(True)
    node.setRenderFlag(True)



def _clear_geo_children(geo) -> None:
    for child in geo.children():
        child.destroy()



def _add_controls(geo) -> None:
    import hou

    # Core settings
    geo.addSpareParmTuple(hou.FloatParmTemplate("intersection_scale", "Intersection Scale", 1, default_value=(1.25,)))
    geo.addSpareParmTuple(hou.FloatParmTemplate("road_y_offset", "Road Y Offset", 1, default_value=(0.0,)))
    geo.addSpareParmTuple(hou.FloatParmTemplate("fuse_distance", "Fuse Distance", 1, default_value=(0.05,)))
    geo.addSpareParmTuple(hou.ToggleParmTemplate("show_debug", "Show Debug", default_value=False))

    # Group widths
    for group in ROAD_GROUPS:
        geo.addSpareParmTuple(
            hou.FloatParmTemplate(f"width_{group.name}", group.label, 1, default_value=(group.default_width,), min=0.05)
        )



def _prepare_input(graph: Graph, input_sop_path: str) -> str:
    """Object-merge input curves and normalize attributes."""

    obj_merge = graph.create("object_merge", "IN_CURVES")
    graph.set_parm("IN_CURVES", "xformtype", 1)
    graph.set_parm("IN_CURVES", "numobj", 1)
    graph.set_parm("IN_CURVES", "objpath1", input_sop_path)

    clean = graph.create("clean", "clean_input")
    graph.connect("clean_input", 0, "IN_CURVES")
    graph.set_parm("clean_input", "fixoverlap", 1)

    to_poly = graph.create("convert", "to_polyline")
    graph.connect("to_polyline", 0, "clean_input")
    graph.set_parm("to_polyline", "totype", 4)

    normalize = graph.create("attribwrangle", "normalize_group")
    graph.connect("normalize_group", 0, "to_polyline")
    normalize.parm("class").set(1)  # primitive
    normalize.parm("snippet").set(
        r'''
string rg = s@road_group;
if (len(rg) == 0) rg = "local";
rg = tolower(rg);
if (rg != "highway" && rg != "primary" && rg != "secondary" && rg != "local") {
    rg = "local";
}
s@road_group = rg;
'''.strip()
    )

    fuse = graph.create("fuse", "fuse_intersections")
    graph.connect("fuse_intersections", 0, "normalize_group")
    graph.set_expr("fuse_intersections", "dist", 'ch("../fuse_distance")')

    return "fuse_intersections"



def _build_group_surface(graph: Graph, source_name: str, group_name: str) -> str:
    """Filter one road_group and convert centerlines to polygon strips."""

    blast = graph.create("blast", f"keep_{group_name}")
    graph.connect(f"keep_{group_name}", 0, source_name)
    graph.set_parm(f"keep_{group_name}", "negate", 1)
    graph.set_parm(f"keep_{group_name}", "group", f'@road_group!="{group_name}"')

    resample = graph.create("resample", f"resample_{group_name}")
    graph.connect(f"resample_{group_name}", 0, f"keep_{group_name}")
    graph.set_parm(f"resample_{group_name}", "dolength", 1)
    graph.set_parm(f"resample_{group_name}", "length", 1.0)

    polyexpand = graph.create("polyexpand2d", f"road_surface_{group_name}")
    graph.connect(f"road_surface_{group_name}", 0, f"resample_{group_name}")
    graph.set_expr(f"road_surface_{group_name}", "offset", f'ch("../width_{group_name}")*0.5')
    graph.set_parm(f"road_surface_{group_name}", "jointstyle", 1)

    color = graph.create("color", f"color_{group_name}")
    graph.connect(f"color_{group_name}", 0, f"road_surface_{group_name}")
    group_color = next(g.color for g in ROAD_GROUPS if g.name == group_name)
    graph.set_parm(f"color_{group_name}", "colorr", group_color[0])
    graph.set_parm(f"color_{group_name}", "colorg", group_color[1])
    graph.set_parm(f"color_{group_name}", "colorb", group_color[2])

    return f"color_{group_name}"



def _build_intersection_points(graph: Graph, centerlines: str) -> str:
    """Detect probable intersections by point valence on fused centerlines."""

    wr = graph.create("attribwrangle", "mark_intersection_points")
    graph.connect("mark_intersection_points", 0, centerlines)
    wr.parm("class").set(2)  # point
    wr.parm("snippet").set(
        r'''
int prims[] = pointprims(0, @ptnum);
i@is_intersection = len(prims) >= 3;
'''.strip()
    )

    blast = graph.create("blast", "keep_intersection_points")
    graph.connect("keep_intersection_points", 0, "mark_intersection_points")
    graph.set_parm("keep_intersection_points", "negate", 1)
    graph.set_parm("keep_intersection_points", "group", "@is_intersection=0")

    return "keep_intersection_points"



def _build_intersection_pads(graph: Graph, intersection_points: str) -> str:
    """Create polygon pads to visually resolve junctions between roads."""

    circle = graph.create("circle", "intersection_pad_proto")
    graph.set_parm("intersection_pad_proto", "type", 1)
    graph.set_expr("intersection_pad_proto", "radx", 'max(ch("../width_local"), ch("../width_secondary"))*0.5*ch("../intersection_scale")')
    graph.set_expr("intersection_pad_proto", "rady", 'max(ch("../width_local"), ch("../width_secondary"))*0.5*ch("../intersection_scale")')

    copy = graph.create("copytopoints", "copy_intersection_pads")
    graph.connect("copy_intersection_pads", 0, "intersection_pad_proto")
    graph.connect("copy_intersection_pads", 1, intersection_points)

    color = graph.create("color", "color_intersections")
    graph.connect("color_intersections", 0, "copy_intersection_pads")
    graph.set_parm("color_intersections", "colorr", 0.18)
    graph.set_parm("color_intersections", "colorg", 0.18)
    graph.set_parm("color_intersections", "colorb", 0.20)

    return "color_intersections"



def _build_debug(graph: Graph, centerlines: str, intersections: str) -> str:
    merge = graph.create("merge", "DEBUG_MERGE")
    graph.connect("DEBUG_MERGE", 0, centerlines)
    graph.connect("DEBUG_MERGE", 1, intersections)

    out = graph.create("null", "OUT_DEBUG")
    graph.connect("OUT_DEBUG", 0, "DEBUG_MERGE")
    return out.name()



def build_curve_road_generator(input_sop_path: str, parent=None, name: str = "curve_road_generator"):
    """Build a roads/intersections generator from artist-drawn curves.

    Args:
        input_sop_path: Absolute Houdini node path to input SOP curves
            (example: `/obj/curve_container/OUT_CURVES`).
        parent: Optional parent node (defaults to `/obj`).
        name: Name of created geo object.

    Returns:
        Created Geometry node.
    """

    import hou

    obj = parent or hou.node("/obj")
    if obj is None:
        raise RuntimeError("Could not find /obj")

    geo = obj.createNode("geo", node_name=name)
    _clear_geo_children(geo)
    _add_controls(geo)

    graph = Graph(geo)

    centerlines = _prepare_input(graph, input_sop_path)

    group_surfaces = []
    for group in ROAD_GROUPS:
        group_surfaces.append(_build_group_surface(graph, centerlines, group.name))

    intersections_pts = _build_intersection_points(graph, centerlines)
    intersection_pads = _build_intersection_pads(graph, intersections_pts)

    merge = graph.create("merge", "merge_roads")
    for i, node_name in enumerate(group_surfaces):
        graph.connect("merge_roads", i, node_name)
    graph.connect("merge_roads", len(group_surfaces), intersection_pads)

    fuse = graph.create("fuse", "fuse_output")
    graph.connect("fuse_output", 0, "merge_roads")
    graph.set_parm("fuse_output", "dist", 0.01)

    lift = graph.create("attribwrangle", "road_height")
    graph.connect("road_height", 0, "fuse_output")
    lift.parm("class").set(2)  # points
    lift.parm("snippet").set('@P.y += ch("../road_y_offset");')

    out = graph.create("null", "OUT_ROADS")
    graph.connect("OUT_ROADS", 0, "road_height")
    _set_display_and_render(out)

    _build_debug(graph, centerlines, intersections_pts)

    geo.layoutChildren()
    return geo



def build_road_generator(input_sop_path: str, parent=None, name: str = "curve_road_generator"):
    """Compatibility alias for previous API naming."""

    return build_curve_road_generator(input_sop_path=input_sop_path, parent=parent, name=name)


if __name__ == "__main__":
    print("Run inside Houdini. Example:")
    print("import houdini_city_generator as gen")
    print("gen.build_curve_road_generator('/obj/curves/OUT_CURVES')")
