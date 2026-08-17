"""Build the redistributable Koko character asset from a CC0 VRoid base.

Run with Blender 4.5 LTS or newer:
  blender --background --python scripts/build_koko_character.py -- base.vrm Koko.usdz preview.png

The source model is Sendagaya_Shino.vrm from madjin/vrm-samples. The model is
one of VRoid Studio's beta sample avatars and is distributed as CC0 by pixiv.
The app's THIRD_PARTY_NOTICES.md records the exact source and license.
"""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def script_arguments() -> tuple[Path, Path, Path]:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- source.vrm output.usdz preview.png")
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 3:
        raise SystemExit("Expected: -- source.vrm output.usdz preview.png")
    return tuple(Path(value).resolve() for value in args)  # type: ignore[return-value]


def vrm_expression_names(path: Path) -> dict[int, str]:
    with path.open("rb") as stream:
        magic, version, _ = struct.unpack("<III", stream.read(12))
        if magic != 0x46546C67 or version != 2:
            raise ValueError("The source is not a GLB-based VRM model")
        json_length, json_type = struct.unpack("<II", stream.read(8))
        if json_type != 0x4E4F534A:
            raise ValueError("The VRM JSON chunk is missing")
        payload = json.loads(stream.read(json_length))

    groups = payload.get("extensions", {}).get("VRM", {}).get("blendShapeMaster", {}).get("blendShapeGroups", [])
    result: dict[int, str] = {}
    aliases = {
        "a": "Mouth_A",
        "i": "Mouth_I",
        "u": "Mouth_U",
        "e": "Mouth_E",
        "o": "Mouth_O",
        "blink": "Blink",
        "blink_l": "Blink_Left",
        "blink_r": "Blink_Right",
        "angry": "Angry",
        "fun": "Fun",
        "joy": "Joy",
        "sorrow": "Sorrow",
    }
    for group in groups:
        raw_name = str(group.get("presetName") or group.get("name") or "Expression").lower()
        friendly = aliases.get(raw_name, str(group.get("name") or "Expression").replace(" ", "_"))
        for binding in group.get("binds", []):
            index = binding.get("index")
            if isinstance(index, int):
                result[index] = friendly
    return result


def look_at(node: bpy.types.Object, target: Vector) -> None:
    direction = target - node.location
    node.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_preview_camera_and_lights(preview_path: Path) -> None:
    camera_data = bpy.data.cameras.new("KokoPreviewCamera")
    camera = bpy.data.objects.new("KokoPreviewCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = (0.0, 3.15, 1.08)
    camera_data.lens = 58
    look_at(camera, Vector((0.0, 0.0, 0.86)))
    bpy.context.scene.camera = camera

    key_data = bpy.data.lights.new("WarmWindowLight", "AREA")
    key_data.energy = 820
    key_data.color = (1.0, 0.78, 0.62)
    key_data.shape = "DISK"
    key_data.size = 4.0
    key = bpy.data.objects.new("WarmWindowLight", key_data)
    bpy.context.scene.collection.objects.link(key)
    key.location = (-2.2, 2.4, 3.3)
    look_at(key, Vector((0.0, 0.0, 0.9)))

    fill_data = bpy.data.lights.new("SkyFill", "AREA")
    fill_data.energy = 520
    fill_data.color = (0.67, 0.82, 1.0)
    fill_data.size = 3.0
    fill = bpy.data.objects.new("SkyFill", fill_data)
    bpy.context.scene.collection.objects.link(fill)
    fill.location = (2.0, 0.4, 2.4)
    look_at(fill, Vector((0.0, 0.0, 1.0)))

    floor_material = bpy.data.materials.new("PreviewFloorMaterial")
    floor_material.diffuse_color = (0.76, 0.55, 0.40, 1.0)
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0.0, 0.0, -0.006))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(floor_material)

    world = bpy.context.scene.world or bpy.data.worlds.new("KokoPreviewWorld")
    bpy.context.scene.world = world
    world.color = (0.055, 0.045, 0.075)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(preview_path)
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)


def main() -> None:
    source_path, output_path, preview_path = script_arguments()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    preview_path.parent.mkdir(parents=True, exist_ok=True)

    expressions = vrm_expression_names(source_path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(source_path), import_pack_images=True)
    if "FINISHED" not in result:
        raise RuntimeError(f"VRM import failed: {result}")

    armature = next((item for item in bpy.context.scene.objects if item.type == "ARMATURE"), None)
    if armature is None:
        raise RuntimeError("The VRM model does not contain an armature")
    armature.name = "KokoRig"
    armature.data.name = "KokoSkeleton"
    armature["character_name"] = "可可"
    armature["asset_schema"] = 1

    for item in list(bpy.context.scene.objects):
        if item.type == "MESH" and (
            item.name.lower().startswith("icosphere")
            or (item.parent is not None and item.parent.name == "secondary")
        ):
            bpy.data.objects.remove(item, do_unlink=True)

    mesh_names = {"Face": "KokoFace", "Body": "KokoBody", "Hair001": "KokoHair"}
    for item in bpy.context.scene.objects:
        if item.name in mesh_names:
            renamed = mesh_names[item.name]
            item.name = renamed
            item.data.name = renamed + "Mesh"
        if item.type == "MESH" and item.data.shape_keys:
            for index, friendly_name in expressions.items():
                key_name = f"target_{index}"
                if key_name in item.data.shape_keys.key_blocks:
                    item.data.shape_keys.key_blocks[key_name].name = friendly_name

    character_objects = [
        item for item in bpy.context.scene.objects
        if item == armature or item.type == "MESH" or (item.type == "EMPTY" and item.name == "Hairs")
    ]
    for item in bpy.context.scene.objects:
        item.select_set(False)
    for item in character_objects:
        item.select_set(True)
    bpy.context.view_layer.objects.active = armature

    bpy.ops.wm.usd_export(
        filepath=str(output_path),
        selected_objects_only=True,
        visible_objects_only=True,
        export_animation=False,
        export_uvmaps=True,
        export_normals=True,
        export_materials=True,
        export_armatures=True,
        only_deform_bones=False,
        export_shapekeys=True,
        generate_preview_surface=True,
        export_textures=True,
        export_textures_mode="KEEP",
        relative_paths=True,
        usdz_downscale_size="1024",
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        convert_scene_units="METERS",
    )

    if not output_path.exists() or output_path.stat().st_size < 100_000:
        raise RuntimeError("USDZ export did not create a valid character asset")

    add_preview_camera_and_lights(preview_path)
    print(
        json.dumps(
            {
                "asset": str(output_path),
                "bytes": output_path.stat().st_size,
                "preview": str(preview_path),
                "bones": len(armature.data.bones),
                "meshes": sum(1 for item in character_objects if item.type == "MESH"),
                "expressions": sorted(set(expressions.values())),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
