#!/usr/bin/env python3
"""Read-only planar layout audit; writes measurements, never game assets.

Example: python tools/audit_map_layout.py --project .
Uses the authored prefab metadata/footprint rectangles, transformed by Godot's
yaw convention. These are not measured render/collision bounds. Roof overhangs,
props, fences, terrain elevations and bridge-deck clearance are outside scope.
"""
import argparse
import itertools
import json
import math
import re
from collections import defaultdict
from pathlib import Path


def point_segment(point, start, finish):
    dx, dz = finish[0] - start[0], finish[1] - start[1]
    denominator = dx * dx + dz * dz
    t = max(0, min(1, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dz) / denominator)) if denominator else 0
    return math.hypot(point[0] - start[0] - t * dx, point[1] - start[1] - t * dz)


def cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def intersect(a, b, c, d):
    if (max(a[0], b[0]) < min(c[0], d[0]) or max(c[0], d[0]) < min(a[0], b[0])
            or max(a[1], b[1]) < min(c[1], d[1]) or max(c[1], d[1]) < min(a[1], b[1])):
        return False
    return cross(a, b, c) * cross(a, b, d) <= 0 and cross(c, d, a) * cross(c, d, b) <= 0


def segment_distance(a, b, c, d):
    return 0.0 if intersect(a, b, c, d) else min(point_segment(a, c, d), point_segment(b, c, d), point_segment(c, a, b), point_segment(d, a, b))


def inside(point, polygon):
    signs = [cross(a, b, point) for a, b in zip(polygon, polygon[1:] + polygon[:1])]
    return min(signs) >= 0 or max(signs) <= 0


def polygon(building, footprints):
    width, depth = footprints[building['prefab']]
    co, si = math.cos(building.get('yaw', 0)), math.sin(building.get('yaw', 0))
    return [(building['x'] + co * x + si * z, building['z'] - si * x + co * z)
            for x, z in [(-width / 2, -depth / 2), (width / 2, -depth / 2), (width / 2, depth / 2), (-width / 2, depth / 2)]]


def segment_polygon_distance(a, b, poly):
    if inside(a, poly) or inside(b, poly):
        return 0.0
    return min(segment_distance(a, b, c, d) for c, d in zip(poly, poly[1:] + poly[:1]))


def polygons_overlap(a, b):
    return (any(inside(p, b) for p in a) or any(inside(p, a) for p in b)
            or any(intersect(p, q, r, s) for p, q in zip(a, a[1:] + a[:1]) for r, s in zip(b, b[1:] + b[:1])))


def building_ref(index, building):
    return {'index': index, 'prefab': building['prefab'], 'poi': building.get('poi', ''),
            'x': building['x'], 'z': building['z']}


def main():
    folder = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=folder.parent)
    parser.add_argument('--prefabs', type=Path)
    parser.add_argument('--output', type=Path, default=folder.parent / 'docs/map/v2/layout-audit.json')
    args = parser.parse_args()
    if args.prefabs is None:
        args.prefabs = args.project / 'world/prefabs/buildings'
    source = args.project.resolve() / 'design/map/slice_2km.json'
    data = json.loads(source.read_text())
    footprints = {}
    for file in args.prefabs.glob('*.tscn'):
        match = re.search(r'metadata/footprint = Vector2\(([^,]+), ([^)]+)\)', file.read_text())
        if match:
            footprints[file.stem] = tuple(map(float, match.groups()))
    missing = sorted({b['prefab'] for b in data['buildings']} - footprints.keys())
    if missing:
        raise ValueError('Missing prefab footprint metadata: ' + ', '.join(missing))

    roads = [r for r in data['roads'] if r['type'] != 'rail']
    segments = [(ri, a, b) for ri, road in enumerate(roads) for a, b in zip(road['points'], road['points'][1:])]
    parent = list(range(len(roads)))

    def root(index):
        while index != parent[index]:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    # Spatial buckets keep the exact segment-distance graph calculation bounded.
    buckets = defaultdict(set)
    for index, (_, a, b) in enumerate(segments):
        for x in range(math.floor((min(a[0], b[0]) - 0.35) / 24), math.floor((max(a[0], b[0]) + 0.35) / 24) + 1):
            for z in range(math.floor((min(a[1], b[1]) - 0.35) / 24), math.floor((max(a[1], b[1]) + 0.35) / 24) + 1):
                buckets[x, z].add(index)
    checked = set()
    for members in buckets.values():
        for i, j in itertools.combinations(members, 2):
            key = (min(i, j), max(i, j))
            if key in checked:
                continue
            checked.add(key)
            ri, a, b = segments[i]
            rj, c, d = segments[j]
            if root(ri) != root(rj) and segment_distance(a, b, c, d) <= 0.35:
                parent[root(ri)] = root(rj)
    components = defaultdict(list)
    for index, road in enumerate(roads):
        components[root(index)].append(road['id'])

    access = []
    for poi in data['pois']:
        distance, road = min((point_segment((poi['x'], poi['z']), a, b) - roads[ri]['width'] / 2, roads[ri]['id']) for ri, a, b in segments)
        access.append({'poi': poi['id'], 'road': road, 'center_to_road_edge_m': round(max(distance, 0), 3)})

    clearances, polygons, radii = [], [], []
    for index, building in enumerate(data['buildings']):
        poly = polygon(building, footprints)
        radius = math.hypot(*footprints[building['prefab']]) / 2
        polygons.append(poly)
        radii.append(radius)
        best, nearest = math.inf, ''
        for ri, a, b in segments:
            half = roads[ri]['width'] / 2
            if point_segment((building['x'], building['z']), a, b) - radius - half > best:
                continue
            clearance = segment_polygon_distance(a, b, poly) - half
            if clearance < best:
                best, nearest = clearance, roads[ri]['id']
        clearances.append(dict(building_ref(index, building), road=nearest, clearance_m=round(best, 4)))

    overlaps = []
    for i, j in itertools.combinations(range(len(data['buildings'])), 2):
        a, b = data['buildings'][i], data['buildings'][j]
        if math.hypot(a['x'] - b['x'], a['z'] - b['z']) <= radii[i] + radii[j] and polygons_overlap(polygons[i], polygons[j]):
            overlaps.append([building_ref(i, a), building_ref(j, b)])

    bridges = []
    for bridge in data.get('bridges', []):
        ends = [(bridge['ax'], bridge['az']), (bridge['bx'], bridge['bz'])]
        distances = [min(point_segment(end, a, b) for _, a, b in segments) for end in ends]
        bridges.append({'id': bridge['id'], 'endpoint_to_road_center_m': [round(d, 4) for d in distances]})
    outside = [{'road': r['id'], 'point': point} for r in data['roads'] for point in r['points']
               if abs(point[0]) > data['halfSizeM'] or abs(point[1]) > data['halfSizeM']]
    road_overlaps = [entry for entry in clearances if entry['clearance_m'] <= 0]
    report = {
        'source': str(source),
        'method': 'Planar segment geometry, authored road widths, rotated metadata/footprint rectangles; railway excluded from road access/obstruction checks.',
        'limitations': ['Footprints are authored metadata approximations, not actual model mesh or collision bounds.',
                        'Roof overhangs, snow dressing, props, fences, wrecks and terrain/bridge elevations are not tested.',
                        'Connectivity is planar at 0.35 m centerline tolerance; separate terrain/grade checks are required.',
                        'Small clearances below 1 m need visual inspection for overhangs and decoration.'],
        'counts': {'buildings': len(data['buildings']), 'pois': len(data['pois']), 'non_rail_routes': len(roads),
                   'road_components': len(components), 'building_road_overlaps': len(road_overlaps),
                   'building_building_overlaps': len(overlaps), 'out_of_bounds_road_points': len(outside)},
        'road_components': list(components.values()), 'poi_access': access,
        'building_road_clearances': sorted(clearances, key=lambda item: item['clearance_m']),
        'building_road_overlaps': road_overlaps, 'building_building_overlaps': overlaps,
        'bridge_endpoints': bridges, 'out_of_bounds_road_points': outside,
    }
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['counts'], indent=2))
    print('Smallest road clearance:', json.dumps(report['building_road_clearances'][0]))
    print('Maximum POI access distance:', max(p['center_to_road_edge_m'] for p in access), 'm')
    print('Report:', args.output.resolve())


if __name__ == '__main__':
    main()
