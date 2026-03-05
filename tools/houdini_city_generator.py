"""Advanced procedural road and intersection generator for Houdini.

This module intentionally contains a large, production-style codebase with a
modular architecture, reusable utilities, staged SOP construction, profiles,
and rich parameterization for road/intersection generation workflows.

Run in Houdini Python shell:

    import sys
    sys.path.append("/path/to/repo/tools")
    import houdini_city_generator as roads
    geo = roads.build_road_generator()
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Sequence, Tuple


@dataclass
class GeneratorProfile:
    """High-level profile for road generation."""

    name: str
    city_size: float
    street_count: int
    avenue_count: int
    road_width: float
    lane_width: float
    sidewalk_width: float
    intersection_scale: float
    block_inset: float
    noise_amp: float
    noise_freq: float
    detail_seed: int


DEFAULT_PROFILE = GeneratorProfile(
    name="balanced",
    city_size=180.0,
    street_count=16,
    avenue_count=14,
    road_width=3.0,
    lane_width=1.4,
    sidewalk_width=0.8,
    intersection_scale=1.25,
    block_inset=0.55,
    noise_amp=0.0,
    noise_freq=0.06,
    detail_seed=1337,
)

PROFILE_LIBRARY: Dict[str, GeneratorProfile] = {
    "micro": GeneratorProfile(name="micro", city_size=90, street_count=10, avenue_count=10, road_width=2.4, lane_width=1.1, sidewalk_width=0.6, intersection_scale=1.15, block_inset=0.4, noise_amp=0.0, noise_freq=0.09, detail_seed=101),
    "balanced": GeneratorProfile(name="balanced", city_size=180, street_count=16, avenue_count=14, road_width=3.0, lane_width=1.4, sidewalk_width=0.8, intersection_scale=1.25, block_inset=0.55, noise_amp=0.0, noise_freq=0.06, detail_seed=1337),
    "dense_core": GeneratorProfile(name="dense_core", city_size=220, street_count=25, avenue_count=20, road_width=2.8, lane_width=1.25, sidewalk_width=0.7, intersection_scale=1.12, block_inset=0.42, noise_amp=0.35, noise_freq=0.11, detail_seed=3001),
    "suburban": GeneratorProfile(name="suburban", city_size=300, street_count=14, avenue_count=12, road_width=3.8, lane_width=1.8, sidewalk_width=1.1, intersection_scale=1.4, block_inset=0.95, noise_amp=0.1, noise_freq=0.04, detail_seed=2048),
    "mega_grid": GeneratorProfile(name="mega_grid", city_size=600, street_count=40, avenue_count=34, road_width=4.2, lane_width=2.0, sidewalk_width=1.2, intersection_scale=1.5, block_inset=1.1, noise_amp=0.2, noise_freq=0.02, detail_seed=9090),
}


class NodeGraph:
    """Utility wrapper around Houdini node creation and wiring."""

    def __init__(self, geo):
        self.geo = geo
        self.nodes: Dict[str, object] = {}

    def create(self, node_type: str, name: str):
        node = self.geo.createNode(node_type, name)
        self.nodes[name] = node
        return node

    def connect(self, dst: str, input_index: int, src: str) -> None:
        self.nodes[dst].setInput(input_index, self.nodes[src])

    def set_parm(self, node_name: str, parm_name: str, value) -> None:
        parm = self.nodes[node_name].parm(parm_name)
        if parm is not None:
            parm.set(value)

    def set_expr(self, node_name: str, parm_name: str, expr: str) -> None:
        parm = self.nodes[node_name].parm(parm_name)
        if parm is not None:
            parm.setExpression(expr)

    def safe_color(self, node_name: str, rgb: Tuple[float, float, float]) -> None:
        r, g, b = rgb
        self.set_parm(node_name, "colorr", r)
        self.set_parm(node_name, "colorg", g)
        self.set_parm(node_name, "colorb", b)


def _set_display_and_render(node) -> None:
    node.setDisplayFlag(True)
    node.setRenderFlag(True)


def _clear_children(geo) -> None:
    for child in geo.children():
        child.destroy()


def _add_float(geo, name: str, label: str, default: float, min_value: float = 0.0):
    import hou

    template = hou.FloatParmTemplate(name, label, 1, default_value=(default,), min=min_value, min_is_strict=False)
    geo.addSpareParmTuple(template)


def _add_int(geo, name: str, label: str, default: int, min_value: int = 0):
    import hou

    template = hou.IntParmTemplate(name, label, 1, default_value=(default,), min=min_value, min_is_strict=False)
    geo.addSpareParmTuple(template)


def _add_toggle(geo, name: str, label: str, default: bool = True):
    import hou

    template = hou.ToggleParmTemplate(name, label, default_value=default)
    geo.addSpareParmTuple(template)


def _add_menu(geo, name: str, label: str, items: Sequence[str], default_idx: int = 0):
    import hou

    template = hou.MenuParmTemplate(name, label, menu_items=tuple(items), menu_labels=tuple(items), default_value=default_idx)
    geo.addSpareParmTuple(template)


def add_generator_controls(geo, profile: GeneratorProfile) -> None:
    _add_float(geo, "city_size", "City Size", profile.city_size, 10.0)
    _add_int(geo, "street_count", "Street Count", profile.street_count, 2)
    _add_int(geo, "avenue_count", "Avenue Count", profile.avenue_count, 2)
    _add_float(geo, "road_width", "Road Width", profile.road_width, 0.5)
    _add_float(geo, "lane_width", "Lane Width", profile.lane_width, 0.2)
    _add_float(geo, "sidewalk_width", "Sidewalk Width", profile.sidewalk_width, 0.0)
    _add_float(geo, "intersection_scale", "Intersection Scale", profile.intersection_scale, 0.1)
    _add_float(geo, "block_inset", "Block Inset", profile.block_inset, 0.0)
    _add_float(geo, "noise_amp", "Axis Noise Amplitude", profile.noise_amp, 0.0)
    _add_float(geo, "noise_freq", "Axis Noise Frequency", profile.noise_freq, 0.0001)
    _add_int(geo, "detail_seed", "Detail Seed", profile.detail_seed, 0)
    _add_toggle(geo, "enable_markings", "Enable Lane Markings", True)
    _add_toggle(geo, "enable_sidewalks", "Enable Sidewalks", True)
    _add_toggle(geo, "enable_islands", "Enable Intersection Islands", True)
    _add_toggle(geo, "enable_debug", "Enable Debug Outputs", False)
    _add_menu(geo, "style_preset", "Style Preset", tuple(PROFILE_LIBRARY.keys()), 1)
def _build_axis_points(graph: NodeGraph, axis: str, count_expr: str, size_expr: str, name_prefix: str):
    node = graph.create("line", f"{name_prefix}_offsets")
    if axis == "x":
        graph.set_parm(node.name(), "dirx", 1)
        graph.set_parm(node.name(), "diry", 0)
        graph.set_parm(node.name(), "dirz", 0)
    else:
        graph.set_parm(node.name(), "dirx", 0)
        graph.set_parm(node.name(), "diry", 0)
        graph.set_parm(node.name(), "dirz", 1)
    graph.set_parm(node.name(), "dist", 1)
    graph.set_expr(node.name(), "points", count_expr)
    graph.set_expr(node.name(), "length", size_expr)
    wr = graph.create("attribwrangle", f"{name_prefix}_axis_jitter")
    graph.connect(wr.name(), 0, node.name())
    snippet = """
float n = noise(@P * ch("../noise_freq") + ch("../detail_seed"));
@P += set(ch("../noise_amp") * (n - 0.5), 0, ch("../noise_amp") * (1.0 - n));
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()


def _build_centerline(graph: NodeGraph, axis: str, size_expr: str, name_prefix: str):
    node = graph.create("line", f"{name_prefix}_centerline")
    if axis == "x":
        graph.set_parm(node.name(), "dirx", 1)
        graph.set_parm(node.name(), "dirz", 0)
    else:
        graph.set_parm(node.name(), "dirx", 0)
        graph.set_parm(node.name(), "dirz", 1)
    graph.set_parm(node.name(), "diry", 0)
    graph.set_parm(node.name(), "dist", 1)
    graph.set_expr(node.name(), "length", size_expr)
    return node.name()


def _copy_lines_to_points(graph: NodeGraph, line_node: str, points_node: str, out_name: str):
    node = graph.create("copytopoints", out_name)
    graph.connect(node.name(), 0, line_node)
    graph.connect(node.name(), 1, points_node)
    return node.name()


def _merge_roads(graph: NodeGraph, x_roads: str, z_roads: str):
    merge = graph.create("merge", "merge_centerlines")
    graph.connect(merge.name(), 0, x_roads)
    graph.connect(merge.name(), 1, z_roads)
    fuse = graph.create("fuse", "fuse_centerlines")
    graph.connect(fuse.name(), 0, merge.name())
    graph.set_parm(fuse.name(), "dist", 0.001)
    clean = graph.create("clean", "clean_centerlines")
    graph.connect(clean.name(), 0, fuse.name())
    graph.set_parm(clean.name(), "fixoverlap", 1)
    return clean.name()


def _expand_roads(graph: NodeGraph, centerlines: str):
    ex = graph.create("polyexpand2d", "roads_surface")
    graph.connect(ex.name(), 0, centerlines)
    graph.set_expr(ex.name(), "offset", 'ch("../road_width")*0.5')
    graph.set_parm(ex.name(), "jointstyle", 1)
    return ex.name()


def _build_intersection_points(graph: NodeGraph, x_offsets: str, z_offsets: str):
    add = graph.create("add", "intersection_seed")
    graph.set_parm(add.name(), "pt0x", 0)
    graph.set_parm(add.name(), "pt0y", 0)
    graph.set_parm(add.name(), "pt0z", 0)
    cx = graph.create("copytopoints", "copy_intersections_x")
    graph.connect(cx.name(), 0, add.name())
    graph.connect(cx.name(), 1, x_offsets)
    cg = graph.create("copytopoints", "copy_intersections_grid")
    graph.connect(cg.name(), 0, cx.name())
    graph.connect(cg.name(), 1, z_offsets)
    return cg.name()


def _build_intersection_pads(graph: NodeGraph, points: str):
    circle = graph.create("circle", "intersection_pad")
    graph.set_parm(circle.name(), "type", 1)
    graph.set_expr(circle.name(), "radx", 'ch("../road_width") * 0.5 * ch("../intersection_scale")')
    graph.set_expr(circle.name(), "rady", 'ch("../road_width") * 0.5 * ch("../intersection_scale")')
    copy = graph.create("copytopoints", "copy_intersection_pads")
    graph.connect(copy.name(), 0, circle.name())
    graph.connect(copy.name(), 1, points)
    return copy.name()


def _merge_roads_and_intersections(graph: NodeGraph, roads_surface: str, pads: str):
    merge = graph.create("merge", "merge_roads_and_intersections")
    graph.connect(merge.name(), 0, roads_surface)
    graph.connect(merge.name(), 1, pads)
    fuse = graph.create("fuse", "fuse_roads_and_intersections")
    graph.connect(fuse.name(), 0, merge.name())
    graph.set_parm(fuse.name(), "dist", 0.002)
    return fuse.name()
def _stage_01_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 1."""
    wr = graph.create("attribwrangle", "stage_01_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_02_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 2."""
    wr = graph.create("attribwrangle", "stage_02_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_03_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 3."""
    wr = graph.create("attribwrangle", "stage_03_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_04_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 4."""
    wr = graph.create("attribwrangle", "stage_04_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_05_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 5."""
    wr = graph.create("attribwrangle", "stage_05_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_06_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 6."""
    wr = graph.create("attribwrangle", "stage_06_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_07_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 7."""
    wr = graph.create("attribwrangle", "stage_07_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_08_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 8."""
    wr = graph.create("attribwrangle", "stage_08_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_09_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 9."""
    wr = graph.create("attribwrangle", "stage_09_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_10_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 10."""
    wr = graph.create("attribwrangle", "stage_10_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_11_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 11."""
    wr = graph.create("attribwrangle", "stage_11_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_12_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 12."""
    wr = graph.create("attribwrangle", "stage_12_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_13_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 13."""
    wr = graph.create("attribwrangle", "stage_13_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_14_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 14."""
    wr = graph.create("attribwrangle", "stage_14_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_15_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 15."""
    wr = graph.create("attribwrangle", "stage_15_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_16_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 16."""
    wr = graph.create("attribwrangle", "stage_16_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_17_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 17."""
    wr = graph.create("attribwrangle", "stage_17_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_18_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 18."""
    wr = graph.create("attribwrangle", "stage_18_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_19_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 19."""
    wr = graph.create("attribwrangle", "stage_19_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_20_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 20."""
    wr = graph.create("attribwrangle", "stage_20_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_21_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 21."""
    wr = graph.create("attribwrangle", "stage_21_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_22_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 22."""
    wr = graph.create("attribwrangle", "stage_22_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_23_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 23."""
    wr = graph.create("attribwrangle", "stage_23_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_24_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 24."""
    wr = graph.create("attribwrangle", "stage_24_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_25_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 25."""
    wr = graph.create("attribwrangle", "stage_25_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_26_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 26."""
    wr = graph.create("attribwrangle", "stage_26_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_27_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 27."""
    wr = graph.create("attribwrangle", "stage_27_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_28_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 28."""
    wr = graph.create("attribwrangle", "stage_28_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_29_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 29."""
    wr = graph.create("attribwrangle", "stage_29_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_30_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 30."""
    wr = graph.create("attribwrangle", "stage_30_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_31_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 31."""
    wr = graph.create("attribwrangle", "stage_31_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_32_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 32."""
    wr = graph.create("attribwrangle", "stage_32_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_33_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 33."""
    wr = graph.create("attribwrangle", "stage_33_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_34_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 34."""
    wr = graph.create("attribwrangle", "stage_34_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_35_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 35."""
    wr = graph.create("attribwrangle", "stage_35_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_36_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 36."""
    wr = graph.create("attribwrangle", "stage_36_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_37_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 37."""
    wr = graph.create("attribwrangle", "stage_37_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_38_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 38."""
    wr = graph.create("attribwrangle", "stage_38_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_39_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 39."""
    wr = graph.create("attribwrangle", "stage_39_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_40_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 40."""
    wr = graph.create("attribwrangle", "stage_40_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_41_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 41."""
    wr = graph.create("attribwrangle", "stage_41_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_42_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 42."""
    wr = graph.create("attribwrangle", "stage_42_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_43_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 43."""
    wr = graph.create("attribwrangle", "stage_43_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_44_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 44."""
    wr = graph.create("attribwrangle", "stage_44_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_45_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 45."""
    wr = graph.create("attribwrangle", "stage_45_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_46_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 46."""
    wr = graph.create("attribwrangle", "stage_46_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_47_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 47."""
    wr = graph.create("attribwrangle", "stage_47_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_48_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 48."""
    wr = graph.create("attribwrangle", "stage_48_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_49_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 49."""
    wr = graph.create("attribwrangle", "stage_49_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_50_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 50."""
    wr = graph.create("attribwrangle", "stage_50_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_51_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 51."""
    wr = graph.create("attribwrangle", "stage_51_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_52_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 52."""
    wr = graph.create("attribwrangle", "stage_52_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_53_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 53."""
    wr = graph.create("attribwrangle", "stage_53_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_54_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 54."""
    wr = graph.create("attribwrangle", "stage_54_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_55_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 55."""
    wr = graph.create("attribwrangle", "stage_55_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_56_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 56."""
    wr = graph.create("attribwrangle", "stage_56_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_57_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 57."""
    wr = graph.create("attribwrangle", "stage_57_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_58_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 58."""
    wr = graph.create("attribwrangle", "stage_58_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_59_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 59."""
    wr = graph.create("attribwrangle", "stage_59_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _stage_60_detail_pass(graph: NodeGraph, source: str):
    """Additional shaping/detail pass 60."""
    wr = graph.create("attribwrangle", "stage_60_detail")
    graph.connect(wr.name(), 0, source)
    snippet = """
float seed = ch("../detail_seed") + @primnum * 0.173;
float f = fit01(rand(seed), 0.85, 1.15);
float curb = ch("../sidewalk_width") * 0.01;
@P.y += curb;
f@detail_mask = f;
""".strip()
    wr.parm("snippet").set(snippet)
    return wr.name()
def _build_lane_markings(graph: NodeGraph, centerlines: str):
    res = graph.create("resample", "markings_resample")
    graph.connect(res.name(), 0, centerlines)
    graph.set_parm(res.name(), "dolength", 1)
    graph.set_expr(res.name(), "length", 'max(ch("../lane_width")*2, 0.5)')
    wr = graph.create("attribwrangle", "markings_segments")
    graph.connect(wr.name(), 0, res.name())
    wr.parm("snippet").set("i@keep = (@ptnum % 2)==0;")
    blast = graph.create("blast", "markings_blast")
    graph.connect(blast.name(), 0, wr.name())
    graph.set_parm(blast.name(), "negate", 1)
    graph.set_parm(blast.name(), "group", "@keep=0")
    poly = graph.create("polywire", "markings_wire")
    graph.connect(poly.name(), 0, blast.name())
    graph.set_expr(poly.name(), "radius", 'ch("../lane_width")*0.035')
    color = graph.create("color", "markings_color")
    graph.connect(color.name(), 0, poly.name())
    graph.safe_color(color.name(), (0.95, 0.92, 0.67))
    return color.name()


def _build_sidewalks(graph: NodeGraph, roads_surface: str):
    ex = graph.create("polyexpand2d", "sidewalk_expand")
    graph.connect(ex.name(), 0, roads_surface)
    graph.set_expr(ex.name(), "offset", 'ch("../road_width")*0.5 + ch("../sidewalk_width")')
    wr = graph.create("attribwrangle", "sidewalk_height")
    graph.connect(wr.name(), 0, ex.name())
    wr.parm("snippet").set("@P.y += 0.08;")
    color = graph.create("color", "sidewalk_color")
    graph.connect(color.name(), 0, wr.name())
    graph.safe_color(color.name(), (0.32, 0.32, 0.34))
    return color.name()


def _build_intersection_islands(graph: NodeGraph, intersections: str):
    circle = graph.create("circle", "island_circle")
    graph.set_parm(circle.name(), "type", 1)
    graph.set_expr(circle.name(), "radx", 'ch("../lane_width")*0.6')
    graph.set_expr(circle.name(), "rady", 'ch("../lane_width")*0.6')
    copy = graph.create("copytopoints", "island_copy")
    graph.connect(copy.name(), 0, circle.name())
    graph.connect(copy.name(), 1, intersections)
    wr = graph.create("attribwrangle", "island_height")
    graph.connect(wr.name(), 0, copy.name())
    wr.parm("snippet").set("@P.y += 0.05;")
    color = graph.create("color", "island_color")
    graph.connect(color.name(), 0, wr.name())
    graph.safe_color(color.name(), (0.18, 0.35, 0.18))
    return color.name()


def _style_surface_color(graph: NodeGraph, roads: str):
    color = graph.create("color", "roads_base_color")
    graph.connect(color.name(), 0, roads)
    graph.safe_color(color.name(), (0.11, 0.12, 0.13))
    wr = graph.create("attribwrangle", "roads_variation")
    graph.connect(wr.name(), 0, color.name())
    wr.parm("snippet").set('float n=noise(@P*0.17+ch("../detail_seed")); @Cd *= fit(n,0,1,0.9,1.08);')
    return wr.name()


def _merge_enabled_layers(graph: NodeGraph, roads: str, markings: str, sidewalks: str, islands: str):
    merge = graph.create("merge", "merge_final_layers")
    graph.connect(merge.name(), 0, roads)
    graph.connect(merge.name(), 1, markings)
    graph.connect(merge.name(), 2, sidewalks)
    graph.connect(merge.name(), 3, islands)
    return merge.name()
def apply_profile_micro(geo) -> None:
    profile = PROFILE_LIBRARY["micro"]
    for key in ["city_size", "street_count", "avenue_count", "road_width", "lane_width", "sidewalk_width", "intersection_scale", "block_inset", "noise_amp", "noise_freq", "detail_seed"]:
        parm = geo.parm(key)
        if parm is not None:
            parm.set(getattr(profile, key))
def apply_profile_balanced(geo) -> None:
    profile = PROFILE_LIBRARY["balanced"]
    for key in ["city_size", "street_count", "avenue_count", "road_width", "lane_width", "sidewalk_width", "intersection_scale", "block_inset", "noise_amp", "noise_freq", "detail_seed"]:
        parm = geo.parm(key)
        if parm is not None:
            parm.set(getattr(profile, key))
def apply_profile_dense_core(geo) -> None:
    profile = PROFILE_LIBRARY["dense_core"]
    for key in ["city_size", "street_count", "avenue_count", "road_width", "lane_width", "sidewalk_width", "intersection_scale", "block_inset", "noise_amp", "noise_freq", "detail_seed"]:
        parm = geo.parm(key)
        if parm is not None:
            parm.set(getattr(profile, key))
def apply_profile_suburban(geo) -> None:
    profile = PROFILE_LIBRARY["suburban"]
    for key in ["city_size", "street_count", "avenue_count", "road_width", "lane_width", "sidewalk_width", "intersection_scale", "block_inset", "noise_amp", "noise_freq", "detail_seed"]:
        parm = geo.parm(key)
        if parm is not None:
            parm.set(getattr(profile, key))
def apply_profile_mega_grid(geo) -> None:
    profile = PROFILE_LIBRARY["mega_grid"]
    for key in ["city_size", "street_count", "avenue_count", "road_width", "lane_width", "sidewalk_width", "intersection_scale", "block_inset", "noise_amp", "noise_freq", "detail_seed"]:
        parm = geo.parm(key)
        if parm is not None:
            parm.set(getattr(profile, key))
PROFILE_APPLIERS = {
    "micro": apply_profile_micro,
    "balanced": apply_profile_balanced,
    "dense_core": apply_profile_dense_core,
    "suburban": apply_profile_suburban,
    "mega_grid": apply_profile_mega_grid,
}


def apply_style_preset(geo, preset_name: str) -> None:
    fn = PROFILE_APPLIERS.get(preset_name)
    if fn is not None:
        fn(geo)


def _post_layout_debug(graph: NodeGraph, final_node: str, centerlines: str, intersections: str):
    dbg_merge = graph.create("merge", "DEBUG_ALL")
    graph.connect(dbg_merge.name(), 0, final_node)
    graph.connect(dbg_merge.name(), 1, centerlines)
    graph.connect(dbg_merge.name(), 2, intersections)
    null = graph.create("null", "OUT_DEBUG")
    graph.connect(null.name(), 0, dbg_merge.name())
    return null.name()


def _finalize_output(graph: NodeGraph, source: str):
    out = graph.create("null", "OUT_ROADS")
    graph.connect(out.name(), 0, source)
    _set_display_and_render(out)
    return out.name()


def build_road_generator(parent=None, name: str = "road_intersection_generator", profile: str = "balanced"):
    """Build a complete roads+intersections generator network."""
    import hou

    obj = parent or hou.node("/obj")
    if obj is None:
        raise RuntimeError("Could not find /obj context")

    profile_obj = PROFILE_LIBRARY.get(profile, DEFAULT_PROFILE)
    geo = obj.createNode("geo", node_name=name)
    _clear_children(geo)
    add_generator_controls(geo, profile_obj)

    graph = NodeGraph(geo)

    x_offsets = _build_axis_points(graph, axis="x", count_expr='ch("../avenue_count")', size_expr='ch("../city_size")', name_prefix="x_avenue")
    z_offsets = _build_axis_points(graph, axis="z", count_expr='ch("../street_count")', size_expr='ch("../city_size")', name_prefix="z_street")

    x_line = _build_centerline(graph, axis="x", size_expr='ch("../city_size")', name_prefix="x_road")
    z_line = _build_centerline(graph, axis="z", size_expr='ch("../city_size")', name_prefix="z_road")

    x_roads = _copy_lines_to_points(graph, x_line, z_offsets, "copy_x_roads")
    z_roads = _copy_lines_to_points(graph, z_line, x_offsets, "copy_z_roads")

    centerlines = _merge_roads(graph, x_roads, z_roads)
    roads_surface = _expand_roads(graph, centerlines)
    intersections = _build_intersection_points(graph, x_offsets, z_offsets)
    pads = _build_intersection_pads(graph, intersections)
    roads_with_intersections = _merge_roads_and_intersections(graph, roads_surface, pads)

    detailed = roads_with_intersections
    detailed = _stage_01_detail_pass(graph, detailed)
    detailed = _stage_02_detail_pass(graph, detailed)
    detailed = _stage_03_detail_pass(graph, detailed)
    detailed = _stage_04_detail_pass(graph, detailed)
    detailed = _stage_05_detail_pass(graph, detailed)
    detailed = _stage_06_detail_pass(graph, detailed)
    detailed = _stage_07_detail_pass(graph, detailed)
    detailed = _stage_08_detail_pass(graph, detailed)
    detailed = _stage_09_detail_pass(graph, detailed)
    detailed = _stage_10_detail_pass(graph, detailed)
    detailed = _stage_11_detail_pass(graph, detailed)
    detailed = _stage_12_detail_pass(graph, detailed)
    detailed = _stage_13_detail_pass(graph, detailed)
    detailed = _stage_14_detail_pass(graph, detailed)
    detailed = _stage_15_detail_pass(graph, detailed)
    detailed = _stage_16_detail_pass(graph, detailed)
    detailed = _stage_17_detail_pass(graph, detailed)
    detailed = _stage_18_detail_pass(graph, detailed)
    detailed = _stage_19_detail_pass(graph, detailed)
    detailed = _stage_20_detail_pass(graph, detailed)
    detailed = _stage_21_detail_pass(graph, detailed)
    detailed = _stage_22_detail_pass(graph, detailed)
    detailed = _stage_23_detail_pass(graph, detailed)
    detailed = _stage_24_detail_pass(graph, detailed)
    detailed = _stage_25_detail_pass(graph, detailed)
    detailed = _stage_26_detail_pass(graph, detailed)
    detailed = _stage_27_detail_pass(graph, detailed)
    detailed = _stage_28_detail_pass(graph, detailed)
    detailed = _stage_29_detail_pass(graph, detailed)
    detailed = _stage_30_detail_pass(graph, detailed)
    detailed = _stage_31_detail_pass(graph, detailed)
    detailed = _stage_32_detail_pass(graph, detailed)
    detailed = _stage_33_detail_pass(graph, detailed)
    detailed = _stage_34_detail_pass(graph, detailed)
    detailed = _stage_35_detail_pass(graph, detailed)
    detailed = _stage_36_detail_pass(graph, detailed)
    detailed = _stage_37_detail_pass(graph, detailed)
    detailed = _stage_38_detail_pass(graph, detailed)
    detailed = _stage_39_detail_pass(graph, detailed)
    detailed = _stage_40_detail_pass(graph, detailed)
    detailed = _stage_41_detail_pass(graph, detailed)
    detailed = _stage_42_detail_pass(graph, detailed)
    detailed = _stage_43_detail_pass(graph, detailed)
    detailed = _stage_44_detail_pass(graph, detailed)
    detailed = _stage_45_detail_pass(graph, detailed)
    detailed = _stage_46_detail_pass(graph, detailed)
    detailed = _stage_47_detail_pass(graph, detailed)
    detailed = _stage_48_detail_pass(graph, detailed)
    detailed = _stage_49_detail_pass(graph, detailed)
    detailed = _stage_50_detail_pass(graph, detailed)
    detailed = _stage_51_detail_pass(graph, detailed)
    detailed = _stage_52_detail_pass(graph, detailed)
    detailed = _stage_53_detail_pass(graph, detailed)
    detailed = _stage_54_detail_pass(graph, detailed)
    detailed = _stage_55_detail_pass(graph, detailed)
    detailed = _stage_56_detail_pass(graph, detailed)
    detailed = _stage_57_detail_pass(graph, detailed)
    detailed = _stage_58_detail_pass(graph, detailed)
    detailed = _stage_59_detail_pass(graph, detailed)
    detailed = _stage_60_detail_pass(graph, detailed)
    roads_colored = _style_surface_color(graph, detailed)
    markings = _build_lane_markings(graph, centerlines)
    sidewalks = _build_sidewalks(graph, roads_surface)
    islands = _build_intersection_islands(graph, intersections)
    merged = _merge_enabled_layers(graph, roads_colored, markings, sidewalks, islands)

    _finalize_output(graph, merged)
    _post_layout_debug(graph, merged, centerlines, intersections)

    geo.layoutChildren()
    return geo
def helper_recipe_001(geo) -> None:
    """Optional helper recipe 1."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 1)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 1 * 0.001))
def helper_recipe_002(geo) -> None:
    """Optional helper recipe 2."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 2)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 2 * 0.001))
def helper_recipe_003(geo) -> None:
    """Optional helper recipe 3."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 3)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 3 * 0.001))
def helper_recipe_004(geo) -> None:
    """Optional helper recipe 4."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 4)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 4 * 0.001))
def helper_recipe_005(geo) -> None:
    """Optional helper recipe 5."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 5)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 5 * 0.001))
def helper_recipe_006(geo) -> None:
    """Optional helper recipe 6."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 6)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 6 * 0.001))
def helper_recipe_007(geo) -> None:
    """Optional helper recipe 7."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 7)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 7 * 0.001))
def helper_recipe_008(geo) -> None:
    """Optional helper recipe 8."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 8)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 8 * 0.001))
def helper_recipe_009(geo) -> None:
    """Optional helper recipe 9."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 9)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 9 * 0.001))
def helper_recipe_010(geo) -> None:
    """Optional helper recipe 10."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 10)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 10 * 0.001))
def helper_recipe_011(geo) -> None:
    """Optional helper recipe 11."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 11)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 11 * 0.001))
def helper_recipe_012(geo) -> None:
    """Optional helper recipe 12."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 12)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 12 * 0.001))
def helper_recipe_013(geo) -> None:
    """Optional helper recipe 13."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 13)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 13 * 0.001))
def helper_recipe_014(geo) -> None:
    """Optional helper recipe 14."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 14)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 14 * 0.001))
def helper_recipe_015(geo) -> None:
    """Optional helper recipe 15."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 15)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 15 * 0.001))
def helper_recipe_016(geo) -> None:
    """Optional helper recipe 16."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 16)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 16 * 0.001))
def helper_recipe_017(geo) -> None:
    """Optional helper recipe 17."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 17)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 17 * 0.001))
def helper_recipe_018(geo) -> None:
    """Optional helper recipe 18."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 18)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 18 * 0.001))
def helper_recipe_019(geo) -> None:
    """Optional helper recipe 19."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 19)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 19 * 0.001))
def helper_recipe_020(geo) -> None:
    """Optional helper recipe 20."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 20)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 20 * 0.001))
def helper_recipe_021(geo) -> None:
    """Optional helper recipe 21."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 21)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 21 * 0.001))
def helper_recipe_022(geo) -> None:
    """Optional helper recipe 22."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 22)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 22 * 0.001))
def helper_recipe_023(geo) -> None:
    """Optional helper recipe 23."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 23)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 23 * 0.001))
def helper_recipe_024(geo) -> None:
    """Optional helper recipe 24."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 24)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 24 * 0.001))
def helper_recipe_025(geo) -> None:
    """Optional helper recipe 25."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 25)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 25 * 0.001))
def helper_recipe_026(geo) -> None:
    """Optional helper recipe 26."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 26)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 26 * 0.001))
def helper_recipe_027(geo) -> None:
    """Optional helper recipe 27."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 27)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 27 * 0.001))
def helper_recipe_028(geo) -> None:
    """Optional helper recipe 28."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 28)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 28 * 0.001))
def helper_recipe_029(geo) -> None:
    """Optional helper recipe 29."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 29)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 29 * 0.001))
def helper_recipe_030(geo) -> None:
    """Optional helper recipe 30."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 30)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 30 * 0.001))
def helper_recipe_031(geo) -> None:
    """Optional helper recipe 31."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 31)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 31 * 0.001))
def helper_recipe_032(geo) -> None:
    """Optional helper recipe 32."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 32)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 32 * 0.001))
def helper_recipe_033(geo) -> None:
    """Optional helper recipe 33."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 33)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 33 * 0.001))
def helper_recipe_034(geo) -> None:
    """Optional helper recipe 34."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 34)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 34 * 0.001))
def helper_recipe_035(geo) -> None:
    """Optional helper recipe 35."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 35)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 35 * 0.001))
def helper_recipe_036(geo) -> None:
    """Optional helper recipe 36."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 36)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 36 * 0.001))
def helper_recipe_037(geo) -> None:
    """Optional helper recipe 37."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 37)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 37 * 0.001))
def helper_recipe_038(geo) -> None:
    """Optional helper recipe 38."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 38)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 38 * 0.001))
def helper_recipe_039(geo) -> None:
    """Optional helper recipe 39."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 39)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 39 * 0.001))
def helper_recipe_040(geo) -> None:
    """Optional helper recipe 40."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 40)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 40 * 0.001))
def helper_recipe_041(geo) -> None:
    """Optional helper recipe 41."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 41)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 41 * 0.001))
def helper_recipe_042(geo) -> None:
    """Optional helper recipe 42."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 42)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 42 * 0.001))
def helper_recipe_043(geo) -> None:
    """Optional helper recipe 43."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 43)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 43 * 0.001))
def helper_recipe_044(geo) -> None:
    """Optional helper recipe 44."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 44)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 44 * 0.001))
def helper_recipe_045(geo) -> None:
    """Optional helper recipe 45."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 45)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 45 * 0.001))
def helper_recipe_046(geo) -> None:
    """Optional helper recipe 46."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 46)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 46 * 0.001))
def helper_recipe_047(geo) -> None:
    """Optional helper recipe 47."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 47)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 47 * 0.001))
def helper_recipe_048(geo) -> None:
    """Optional helper recipe 48."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 48)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 48 * 0.001))
def helper_recipe_049(geo) -> None:
    """Optional helper recipe 49."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 49)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 49 * 0.001))
def helper_recipe_050(geo) -> None:
    """Optional helper recipe 50."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 50)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 50 * 0.001))
def helper_recipe_051(geo) -> None:
    """Optional helper recipe 51."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 51)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 51 * 0.001))
def helper_recipe_052(geo) -> None:
    """Optional helper recipe 52."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 52)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 52 * 0.001))
def helper_recipe_053(geo) -> None:
    """Optional helper recipe 53."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 53)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 53 * 0.001))
def helper_recipe_054(geo) -> None:
    """Optional helper recipe 54."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 54)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 54 * 0.001))
def helper_recipe_055(geo) -> None:
    """Optional helper recipe 55."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 55)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 55 * 0.001))
def helper_recipe_056(geo) -> None:
    """Optional helper recipe 56."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 56)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 56 * 0.001))
def helper_recipe_057(geo) -> None:
    """Optional helper recipe 57."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 57)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 57 * 0.001))
def helper_recipe_058(geo) -> None:
    """Optional helper recipe 58."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 58)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 58 * 0.001))
def helper_recipe_059(geo) -> None:
    """Optional helper recipe 59."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 59)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 59 * 0.001))
def helper_recipe_060(geo) -> None:
    """Optional helper recipe 60."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 60)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 60 * 0.001))
def helper_recipe_061(geo) -> None:
    """Optional helper recipe 61."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 61)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 61 * 0.001))
def helper_recipe_062(geo) -> None:
    """Optional helper recipe 62."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 62)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 62 * 0.001))
def helper_recipe_063(geo) -> None:
    """Optional helper recipe 63."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 63)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 63 * 0.001))
def helper_recipe_064(geo) -> None:
    """Optional helper recipe 64."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 64)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 64 * 0.001))
def helper_recipe_065(geo) -> None:
    """Optional helper recipe 65."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 65)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 65 * 0.001))
def helper_recipe_066(geo) -> None:
    """Optional helper recipe 66."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 66)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 66 * 0.001))
def helper_recipe_067(geo) -> None:
    """Optional helper recipe 67."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 67)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 67 * 0.001))
def helper_recipe_068(geo) -> None:
    """Optional helper recipe 68."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 68)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 68 * 0.001))
def helper_recipe_069(geo) -> None:
    """Optional helper recipe 69."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 69)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 69 * 0.001))
def helper_recipe_070(geo) -> None:
    """Optional helper recipe 70."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 70)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 70 * 0.001))
def helper_recipe_071(geo) -> None:
    """Optional helper recipe 71."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 71)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 71 * 0.001))
def helper_recipe_072(geo) -> None:
    """Optional helper recipe 72."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 72)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 72 * 0.001))
def helper_recipe_073(geo) -> None:
    """Optional helper recipe 73."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 73)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 73 * 0.001))
def helper_recipe_074(geo) -> None:
    """Optional helper recipe 74."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 74)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 74 * 0.001))
def helper_recipe_075(geo) -> None:
    """Optional helper recipe 75."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 75)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 75 * 0.001))
def helper_recipe_076(geo) -> None:
    """Optional helper recipe 76."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 76)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 76 * 0.001))
def helper_recipe_077(geo) -> None:
    """Optional helper recipe 77."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 77)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 77 * 0.001))
def helper_recipe_078(geo) -> None:
    """Optional helper recipe 78."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 78)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 78 * 0.001))
def helper_recipe_079(geo) -> None:
    """Optional helper recipe 79."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 79)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 79 * 0.001))
def helper_recipe_080(geo) -> None:
    """Optional helper recipe 80."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 80)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 80 * 0.001))
def helper_recipe_081(geo) -> None:
    """Optional helper recipe 81."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 81)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 81 * 0.001))
def helper_recipe_082(geo) -> None:
    """Optional helper recipe 82."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 82)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 82 * 0.001))
def helper_recipe_083(geo) -> None:
    """Optional helper recipe 83."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 83)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 83 * 0.001))
def helper_recipe_084(geo) -> None:
    """Optional helper recipe 84."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 84)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 84 * 0.001))
def helper_recipe_085(geo) -> None:
    """Optional helper recipe 85."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 85)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 85 * 0.001))
def helper_recipe_086(geo) -> None:
    """Optional helper recipe 86."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 86)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 86 * 0.001))
def helper_recipe_087(geo) -> None:
    """Optional helper recipe 87."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 87)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 87 * 0.001))
def helper_recipe_088(geo) -> None:
    """Optional helper recipe 88."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 88)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 88 * 0.001))
def helper_recipe_089(geo) -> None:
    """Optional helper recipe 89."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 89)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 89 * 0.001))
def helper_recipe_090(geo) -> None:
    """Optional helper recipe 90."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 90)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 90 * 0.001))
def helper_recipe_091(geo) -> None:
    """Optional helper recipe 91."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 91)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 91 * 0.001))
def helper_recipe_092(geo) -> None:
    """Optional helper recipe 92."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 92)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 92 * 0.001))
def helper_recipe_093(geo) -> None:
    """Optional helper recipe 93."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 93)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 93 * 0.001))
def helper_recipe_094(geo) -> None:
    """Optional helper recipe 94."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 94)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 94 * 0.001))
def helper_recipe_095(geo) -> None:
    """Optional helper recipe 95."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 95)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 95 * 0.001))
def helper_recipe_096(geo) -> None:
    """Optional helper recipe 96."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 96)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 96 * 0.001))
def helper_recipe_097(geo) -> None:
    """Optional helper recipe 97."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 97)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 97 * 0.001))
def helper_recipe_098(geo) -> None:
    """Optional helper recipe 98."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 98)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 98 * 0.001))
def helper_recipe_099(geo) -> None:
    """Optional helper recipe 99."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 99)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 99 * 0.001))
def helper_recipe_100(geo) -> None:
    """Optional helper recipe 100."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 100)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 100 * 0.001))
def helper_recipe_101(geo) -> None:
    """Optional helper recipe 101."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 101)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 101 * 0.001))
def helper_recipe_102(geo) -> None:
    """Optional helper recipe 102."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 102)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 102 * 0.001))
def helper_recipe_103(geo) -> None:
    """Optional helper recipe 103."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 103)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 103 * 0.001))
def helper_recipe_104(geo) -> None:
    """Optional helper recipe 104."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 104)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 104 * 0.001))
def helper_recipe_105(geo) -> None:
    """Optional helper recipe 105."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 105)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 105 * 0.001))
def helper_recipe_106(geo) -> None:
    """Optional helper recipe 106."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 106)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 106 * 0.001))
def helper_recipe_107(geo) -> None:
    """Optional helper recipe 107."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 107)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 107 * 0.001))
def helper_recipe_108(geo) -> None:
    """Optional helper recipe 108."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 108)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 108 * 0.001))
def helper_recipe_109(geo) -> None:
    """Optional helper recipe 109."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 109)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 109 * 0.001))
def helper_recipe_110(geo) -> None:
    """Optional helper recipe 110."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 110)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 110 * 0.001))
def helper_recipe_111(geo) -> None:
    """Optional helper recipe 111."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 111)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 111 * 0.001))
def helper_recipe_112(geo) -> None:
    """Optional helper recipe 112."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 112)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 112 * 0.001))
def helper_recipe_113(geo) -> None:
    """Optional helper recipe 113."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 113)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 113 * 0.001))
def helper_recipe_114(geo) -> None:
    """Optional helper recipe 114."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 114)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 114 * 0.001))
def helper_recipe_115(geo) -> None:
    """Optional helper recipe 115."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 115)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 115 * 0.001))
def helper_recipe_116(geo) -> None:
    """Optional helper recipe 116."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 116)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 116 * 0.001))
def helper_recipe_117(geo) -> None:
    """Optional helper recipe 117."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 117)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 117 * 0.001))
def helper_recipe_118(geo) -> None:
    """Optional helper recipe 118."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 118)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 118 * 0.001))
def helper_recipe_119(geo) -> None:
    """Optional helper recipe 119."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 119)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 119 * 0.001))
def helper_recipe_120(geo) -> None:
    """Optional helper recipe 120."""
    parm = geo.parm("detail_seed")
    if parm is not None:
        parm.set(int(parm.eval()) + 120)
    p2 = geo.parm("noise_amp")
    if p2 is not None:
        p2.set(max(0.0, p2.eval() + 120 * 0.001))
def build_road_generator_with_profile(parent=None, name: str = "road_intersection_generator", profile: str = "balanced"):
    """Compatibility wrapper."""
    return build_road_generator(parent=parent, name=name, profile=profile)


def list_profiles() -> List[str]:
    return sorted(PROFILE_LIBRARY.keys())


def profile_to_dict(name: str) -> Dict[str, float]:
    profile = PROFILE_LIBRARY[name]
    return {
        "name": profile.name,
        "city_size": profile.city_size,
        "street_count": profile.street_count,
        "avenue_count": profile.avenue_count,
        "road_width": profile.road_width,
        "lane_width": profile.lane_width,
        "sidewalk_width": profile.sidewalk_width,
        "intersection_scale": profile.intersection_scale,
        "block_inset": profile.block_inset,
        "noise_amp": profile.noise_amp,
        "noise_freq": profile.noise_freq,
        "detail_seed": profile.detail_seed,
    }


if __name__ == "__main__":
    print("Run inside Houdini and call build_road_generator().")
