#!/usr/bin/env python3
from typing import Optional
"""AVAP 打包脚本 — 从 Godot 项目中收集 AVAP 资源并准备打包

功能:
1. 扫描 .tscn/.tres 文件，提取所有 AVAPResource 引用
2. 按 tag 分组
3. 生成 Godot 导出排除列表（原始视频不进 PCK）
4. 输出打包清单（JSON），供后续 binpack + 编码使用

用法:
  python3 avap_pack.py --project /path/to/godot_project [--config avap_pack_config.tres]
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


def scan_avap_resources(project_dir: str) -> list[dict]:
    """扫描项目里所有 .tscn/.tres 文件，提取 AVAPResource 引用"""
    resources = []
    
    for ext in ("*.tscn", "*.tres"):
        for filepath in Path(project_dir).rglob(ext):
            content = filepath.read_text(encoding="utf-8", errors="ignore")
            resources.extend(_parse_avap_resources(content, str(filepath)))
    
    return resources


def _parse_avap_resources(content: str, source_file: str) -> list[dict]:
    """从场景/资源文件内容中提取 AVAPResource 数据
    
    Godot 序列化格式示例:
    [ext_resource type="AVAPResource" uid="uid://xxx" path="res://effects/slash.tres"]
    
    或内联:
    [sub_resource type="AVAPResource" id="AVAPResource_xxx"]
    video_path = "res://effects/slash.webm"
    tag = "battle"
    loop_mode = 0
    speed_scale = 1.0
    autoplay = false
    """
    results = []
    
    # 匹配 AVAPResource 的 sub_resource 块
    pattern = re.compile(
        r'\[sub_resource type="AVAPResource"[^\]]*\]\s*'
        r'(.*?)(?=\n\[|\Z)',
        re.DOTALL
    )
    
    for match in pattern.finditer(content):
        block = match.group(1)
        res = _parse_resource_block(block, source_file)
        if res and res.get("video_path"):
            results.append(res)
    
    # 匹配 ext_resource 引用（需要加载 .tres 文件读取内容）
    ext_pattern = re.compile(
        r'\[ext_resource type="AVAPResource"[^\]]*path="([^"]+)"'
    )
    for match in ext_pattern.finditer(content):
        tres_path = match.group(1)
        # 标记为外部引用，后续需要加载
        results.append({
            "_type": "ext_reference",
            "_tres_path": tres_path,
            "_source_file": source_file,
        })
    
    return results


def _parse_resource_block(block: str, source_file: str) -> Optional[dict]:
    """解析单个 AVAPResource 属性块"""
    res = {"_source_file": source_file}
    
    for line in block.strip().split("\n"):
        line = line.strip()
        if "=" not in line:
            continue
        
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"')
        
        if key == "video_path":
            res["video_path"] = value
        elif key == "tag":
            res["tag"] = value if value else "default"
        elif key == "loop_mode":
            res["loop_mode"] = int(value) if value.isdigit() else 0
        elif key == "speed_scale":
            res["speed_scale"] = float(value) if value else 1.0
        elif key == "autoplay":
            res["autoplay"] = value.lower() == "true"
    
    return res if "video_path" in res else None


def resolve_ext_references(resources: list[dict], project_dir: str) -> list[dict]:
    """加载 ext_resource 引用的 .tres 文件"""
    resolved = []
    
    for res in resources:
        if res.get("_type") == "ext_reference":
            tres_path = res["_tres_path"].replace("res://", "")
            tres_file = Path(project_dir) / tres_path
            if tres_file.exists():
                content = tres_file.read_text(encoding="utf-8", errors="ignore")
                parsed = _parse_resource_block(content, str(tres_file))
                if parsed:
                    parsed["_source_file"] = res["_source_file"]
                    resolved.append(parsed)
        else:
            resolved.append(res)
    
    return resolved


def group_by_tag(resources: list[dict]) -> dict[str, list[dict]]:
    """按 tag 分组"""
    groups = defaultdict(list)
    for res in resources:
        tag = res.get("tag", "default")
        groups[tag].append(res)
    return dict(groups)


def generate_exclude_list(resources: list[dict]) -> list[str]:
    """生成 Godot 导出排除列表（原始视频文件路径）"""
    excludes = set()
    for res in resources:
        video_path = res.get("video_path", "")
        if video_path:
            # res://effects/slash.webm → effects/slash.webm
            rel_path = video_path.replace("res://", "")
            excludes.add(rel_path)
    return sorted(excludes)


def generate_pack_manifest(groups: dict[str, list[dict]], config: Optional[dict] = None) -> dict:
    """生成打包清单"""
    manifest = {
        "version": 1,
        "tags": {},
    }
    
    for tag, items in groups.items():
        tag_config = {}
        if config and "tag_overrides" in config and tag in config["tag_overrides"]:
            tag_config = config["tag_overrides"][tag]
        
        manifest["tags"][tag] = {
            "videos": [
                {
                    "video_path": item["video_path"],
                    "animation_name": item.get("animation_name", Path(item["video_path"]).stem),
                    "source_scene": item.get("_source_file", ""),
                }
                for item in items
            ],
            "compression": tag_config if tag_config else "global",
        }
    
    return manifest


def update_export_presets(project_dir: str, excludes: list[str]) -> bool:
    """更新 Godot 的 export_presets.cfg，添加排除列表"""
    cfg_path = Path(project_dir) / "export_presets.cfg"
    if not cfg_path.exists():
        print(f"警告: {cfg_path} 不存在，跳过更新")
        return False
    
    content = cfg_path.read_text(encoding="utf-8")
    
    # 构建排除过滤字符串
    exclude_str = ", ".join(f'"{e}"' for e in excludes)
    
    # 查找并更新每个 preset 的 exclude_filter
    # Godot 格式: exclude_filter="xxx,yyy"
    pattern = re.compile(r'(exclude_filter=")([^"]*)(")')
    
    def replacer(match):
        existing = match.group(2)
        if existing:
            new_filter = existing + ", " + exclude_str
        else:
            new_filter = exclude_str
        return match.group(1) + new_filter + match.group(3)
    
    new_content = pattern.sub(replacer, content)
    
    if new_content != content:
        cfg_path.write_text(new_content, encoding="utf-8")
        print(f"已更新 {cfg_path.name}，排除 {len(excludes)} 个视频文件")
        return True
    
    print("export_presets.cfg 无需更新")
    return False


def main():
    parser = argparse.ArgumentParser(description="AVAP 打包脚本")
    parser.add_argument("--project", required=True, help="Godot 项目目录")
    parser.add_argument("--config", default=None, help="AVAPPackConfig .tres 文件路径")
    parser.add_argument("--dry-run", action="store_true", help="只输出结果，不修改文件")
    parser.add_argument("--output", default="avap_manifest.json", help="打包清单输出路径")
    args = parser.parse_args()
    
    project_dir = os.path.abspath(args.project)
    print(f"扫描项目: {project_dir}")
    
    # 1. 扫描 AVAPResource
    resources = scan_avap_resources(project_dir)
    resources = resolve_ext_references(resources, project_dir)
    
    if not resources:
        print("未找到 AVAPResource 引用")
        sys.exit(0)
    
    print(f"找到 {len(resources)} 个 AVAPResource 引用")
    
    # 2. 按 tag 分组
    groups = group_by_tag(resources)
    for tag, items in groups.items():
        print(f"  [{tag}]: {len(items)} 个动画")
    
    # 3. 生成排除列表
    excludes = generate_exclude_list(resources)
    print(f"\n排除 {len(excludes)} 个原始视频文件（不进 PCK）:")
    for e in excludes:
        print(f"  - {e}")
    
    # 4. 更新导出配置
    if not args.dry_run:
        update_export_presets(project_dir, excludes)
    
    # 5. 生成打包清单
    manifest = generate_pack_manifest(groups)
    output_path = args.output
    if not args.dry_run:
        Path(output_path).write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False),
            encoding="utf-8"
        )
        print(f"\n打包清单已写入: {output_path}")
    else:
        print(f"\n打包清单（dry-run）:")
        print(json.dumps(manifest, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
