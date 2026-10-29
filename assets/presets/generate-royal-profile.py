#!/usr/bin/env python3
"""Build a static Royal choreography profile from the canonical preset.

Balanced is copied byte-for-byte. Calm and intense curate mirrored or
counter-rotating ambient arcs, mote movement, color-role assignments, and
separate comet and hard-impact paths. The profiles share detector/envelope
equations, palette generation, zoom, and fixed particle limits.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

MODULE_PREFIX = "const preset: Record<string, any> = "
MODULE_SUFFIX = ";\n\nexport default preset;\n"

# MilkDrop source edits are anchored to equation keys. The matching Butterchurn
# edits below preserve parity between projectM's .milk and Feishin's module.
PROFILE_CHANGES = {
    'calm': {
        'milk': [
            ('wave_0_per_point9', 'x = 0.5 + (x-0.5)*q25;', 'x = 0.5 - (x-0.5)*q25;'),
            (
                'wave_2_per_point12',
                'arcPhase = (sample-0.5)*4.2 + time*0.12;',
                'arcPhase = (sample-0.5)*4.2 - time*0.08;',
            ),
            (
                'shape_1_per_frame3',
                'angle = instance*2.39996322973 + time*0.025;',
                'angle = instance*2.39996322973 + time*0.015;',
            ),
            ('shape_1_per_frame7', 'ang = time*0.12 + instance;', 'ang = time*0.08 + instance;'),
            ('wave_1_per_point15', 'r = q9*shade;', 'r = q12*shade;'),
            ('wave_1_per_point16', 'g = q10*shade;', 'g = q13*shade;'),
            ('wave_1_per_point17', 'b = q11*shade;', 'b = q14*shade;'),
            ('wave_2_per_point19', 'r = q12*shade;', 'r = q9*shade;'),
            ('wave_2_per_point20', 'g = q13*shade;', 'g = q10*shade;'),
            ('wave_2_per_point21', 'b = q14*shade;', 'b = q11*shade;'),
            ('wave_3_per_point3', 'impactRadius = 0.12 + q5*0.06;', 'impactRadius = 0.10 + q5*0.05;'),
            ('wave_3_per_point4', 'time*0.25', 'time*0.16'),
            (
                'wave_3_per_point8',
                'cometPhase = (sample-0.5)*4.2 + time*0.03;',
                'cometPhase = (sample-0.5)*4.2 - time*0.025;',
            ),
            ('wave_3_per_point13', '0.12*cos(cometPhase)', '0.10*cos(cometPhase)'),
            ('wave_3_per_point14', '0.12*0.72*sin(cometPhase)', '0.10*0.72*sin(cometPhase)'),
            (
                'shape_3_per_frame3',
                'angle = (progress-0.5)*4.2 + time*0.03;',
                'angle = (progress-0.5)*4.2 - time*0.025;',
            ),
            ('shape_3_per_frame4', '0.12*0.8*cos(angle)', '0.10*0.8*cos(angle)'),
            ('shape_3_per_frame5', '0.12*0.72*0.8*sin(angle)', '0.10*0.72*0.8*sin(angle)'),
        ],
        'module': [
            ('waves', 0, 'point_eqs_eel', 'x = 0.5 + (x-0.5)*q25;', 'x = 0.5 - (x-0.5)*q25;'),
            (
                'waves',
                0,
                'point_eqs_str',
                "a['x']=(0.5+((a['x']-0.5)*a['q25']));",
                "a['x']=(0.5-((a['x']-0.5)*a['q25']));",
            ),
            (
                'waves',
                2,
                'point_eqs_eel',
                'arcPhase = (sample-0.5)*4.2 + time*0.12;',
                'arcPhase = (sample-0.5)*4.2 - time*0.08;',
            ),
            (
                'waves',
                2,
                'point_eqs_str',
                "a['arcphase']=(((a['sample']-0.5)*4.2)+(a['time']*0.12));",
                "a['arcphase']=(((a['sample']-0.5)*4.2)-(a['time']*0.08));",
            ),
            (
                'shapes',
                1,
                'frame_eqs_eel',
                'angle = instance*2.39996322973 + time*0.025;',
                'angle = instance*2.39996322973 + time*0.015;',
            ),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['angle']=((a['instance']*2.39996322973)+(a['time']*0.025));",
                "a['angle']=((a['instance']*2.39996322973)+(a['time']*0.015));",
            ),
            ('shapes', 1, 'frame_eqs_eel', 'ang = time*0.12 + instance;', 'ang = time*0.08 + instance;'),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['ang']=((a['time']*0.12)+a['instance']);",
                "a['ang']=((a['time']*0.08)+a['instance']);",
            ),
            ('waves', 1, 'point_eqs_eel', 'r = q9*shade;', 'r = q12*shade;'),
            ('waves', 1, 'point_eqs_eel', 'g = q10*shade;', 'g = q13*shade;'),
            ('waves', 1, 'point_eqs_eel', 'b = q11*shade;', 'b = q14*shade;'),
            ('waves', 1, 'point_eqs_str', "a['r']=(a['q9']*a['shade']);", "a['r']=(a['q12']*a['shade']);"),
            ('waves', 1, 'point_eqs_str', "a['g']=(a['q10']*a['shade']);", "a['g']=(a['q13']*a['shade']);"),
            ('waves', 1, 'point_eqs_str', "a['b']=(a['q11']*a['shade']);", "a['b']=(a['q14']*a['shade']);"),
            ('waves', 2, 'point_eqs_eel', 'r = q12*shade;', 'r = q9*shade;'),
            ('waves', 2, 'point_eqs_eel', 'g = q13*shade;', 'g = q10*shade;'),
            ('waves', 2, 'point_eqs_eel', 'b = q14*shade;', 'b = q11*shade;'),
            ('waves', 2, 'point_eqs_str', "a['r']=(a['q12']*a['shade']);", "a['r']=(a['q9']*a['shade']);"),
            ('waves', 2, 'point_eqs_str', "a['g']=(a['q13']*a['shade']);", "a['g']=(a['q10']*a['shade']);"),
            ('waves', 2, 'point_eqs_str', "a['b']=(a['q14']*a['shade']);", "a['b']=(a['q11']*a['shade']);"),
            ('waves', 3, 'point_eqs_eel', 'impactRadius = 0.12 + q5*0.06;', 'impactRadius = 0.10 + q5*0.05;'),
            (
                'waves',
                3,
                'point_eqs_str',
                "a['impactradius']=(0.12+(a['q5']*0.06));",
                "a['impactradius']=(0.10+(a['q5']*0.05));",
            ),
            (
                'waves',
                3,
                'point_eqs_eel',
                'impactPhase = (sample-0.5)*4.2 + time*0.25 + stereo*0.18;',
                'impactPhase = (sample-0.5)*4.2 + time*0.16 + stereo*0.18;',
            ),
            (
                'waves',
                3,
                'point_eqs_str',
                "a['impactphase']=((((a['sample']-0.5)*4.2)+(a['time']*0.25))+(a['stereo']*0.18));",
                "a['impactphase']=((((a['sample']-0.5)*4.2)+(a['time']*0.16))+(a['stereo']*0.18));",
            ),
            (
                'waves',
                3,
                'point_eqs_eel',
                'cometPhase = (sample-0.5)*4.2 + time*0.03;',
                'cometPhase = (sample-0.5)*4.2 - time*0.025;',
            ),
            (
                'waves',
                3,
                'point_eqs_str',
                "a['cometphase']=(((a['sample']-0.5)*4.2)+(a['time']*0.03));",
                "a['cometphase']=(((a['sample']-0.5)*4.2)-(a['time']*0.025));",
            ),
            ('waves', 3, 'point_eqs_eel', '0.12*cos(cometPhase)', '0.10*cos(cometPhase)'),
            ('waves', 3, 'point_eqs_str', "0.12*Math.cos(a['cometphase'])", "0.10*Math.cos(a['cometphase'])"),
            ('waves', 3, 'point_eqs_eel', '0.12*0.72*sin(cometPhase)', '0.10*0.72*sin(cometPhase)'),
            (
                'waves',
                3,
                'point_eqs_str',
                "(0.12*0.72)*Math.sin(a['cometphase'])",
                "(0.10*0.72)*Math.sin(a['cometphase'])",
            ),
            (
                'shapes',
                3,
                'frame_eqs_eel',
                'angle = (progress-0.5)*4.2 + time*0.03;',
                'angle = (progress-0.5)*4.2 - time*0.025;',
            ),
            (
                'shapes',
                3,
                'frame_eqs_str',
                "a['angle']=(((a['progress']-0.5)*4.2)+(a['time']*0.03));",
                "a['angle']=(((a['progress']-0.5)*4.2)-(a['time']*0.025));",
            ),
            ('shapes', 3, 'frame_eqs_eel', '0.12*0.8*cos(angle)', '0.10*0.8*cos(angle)'),
            (
                'shapes',
                3,
                'frame_eqs_str',
                "(0.12*0.8)*Math.cos(a['angle'])",
                "(0.10*0.8)*Math.cos(a['angle'])",
            ),
            ('shapes', 3, 'frame_eqs_eel', '0.12*0.72*0.8*sin(angle)', '0.10*0.72*0.8*sin(angle)'),
            (
                'shapes',
                3,
                'frame_eqs_str',
                "((0.12*0.72)*0.8)*Math.sin(a['angle'])",
                "((0.10*0.72)*0.8)*Math.sin(a['angle'])",
            ),
        ],
    },
    'intense': {
        'milk': [
            ('wave_1_per_point11', 'x = 0.5 + (x-0.5)*q25;', 'x = 0.5 - (x-0.5)*q25;'),
            ('wave_1_per_point1', 'speed = bass_att*0.8;', 'speed = bass_att*1.15;'),
            (
                'wave_2_per_point12',
                'arcPhase = (sample-0.5)*4.2 + time*0.12;',
                'arcPhase = (sample-0.5)*4.2 + time*0.28;',
            ),
            ('wave_2_per_point13', '0.28*cos(arcPhase)', '0.22*cos(arcPhase)'),
            ('wave_2_per_point14', '0.28*0.72*sin(arcPhase)', '0.22*0.72*sin(arcPhase)'),
            (
                'shape_1_per_frame3',
                'angle = instance*2.39996322973 + time*0.025;',
                'angle = instance*2.39996322973 - time*0.10;',
            ),
            ('shape_1_per_frame7', 'ang = time*0.12 + instance;', 'ang = -time*0.32 + instance;'),
            ('shape_1_per_frame9', 'r = q9*(1-pick) + q12*pick;', 'r = q15*(1-pick) + q12*pick;'),
            ('shape_1_per_frame10', 'g = q10*(1-pick) + q13*pick;', 'g = q16*(1-pick) + q13*pick;'),
            ('shape_1_per_frame11', 'b = q11*(1-pick) + q14*pick;', 'b = q17*(1-pick) + q14*pick;'),
            ('wave_3_per_point3', 'impactRadius = 0.12 + q5*0.06;', 'impactRadius = 0.15 + q5*0.08;'),
            ('wave_3_per_point4', 'time*0.25', 'time*0.38'),
            (
                'wave_3_per_point8',
                'cometPhase = (sample-0.5)*4.2 + time*0.03;',
                'cometPhase = (sample-0.5)*4.2 + time*0.18;',
            ),
            ('wave_3_per_point13', '0.12*cos(cometPhase)', '0.15*cos(cometPhase)'),
            ('wave_3_per_point14', '0.12*0.72*sin(cometPhase)', '0.15*0.72*sin(cometPhase)'),
            (
                'shape_3_per_frame3',
                'angle = (progress-0.5)*4.2 + time*0.03;',
                'angle = (progress-0.5)*4.2 + time*0.18;',
            ),
            ('shape_3_per_frame4', '0.12*0.8*cos(angle)', '0.15*0.8*cos(angle)'),
            ('shape_3_per_frame5', '0.12*0.72*0.8*sin(angle)', '0.15*0.72*0.8*sin(angle)'),
        ],
        'module': [
            ('waves', 1, 'point_eqs_eel', 'x = 0.5 + (x-0.5)*q25;', 'x = 0.5 - (x-0.5)*q25;'),
            (
                'waves',
                1,
                'point_eqs_str',
                "a['x']=(0.5+((a['x']-0.5)*a['q25']));",
                "a['x']=(0.5-((a['x']-0.5)*a['q25']));",
            ),
            ('waves', 1, 'point_eqs_eel', 'speed = bass_att*0.8;', 'speed = bass_att*1.15;'),
            (
                'waves',
                1,
                'point_eqs_str',
                "a['speed']=(a['bass_att']*0.8);",
                "a['speed']=(a['bass_att']*1.15);",
            ),
            (
                'waves',
                2,
                'point_eqs_eel',
                'arcPhase = (sample-0.5)*4.2 + time*0.12;',
                'arcPhase = (sample-0.5)*4.2 + time*0.28;',
            ),
            (
                'waves',
                2,
                'point_eqs_str',
                "a['arcphase']=(((a['sample']-0.5)*4.2)+(a['time']*0.12));",
                "a['arcphase']=(((a['sample']-0.5)*4.2)+(a['time']*0.28));",
            ),
            ('waves', 2, 'point_eqs_eel', '0.28*cos(arcPhase)', '0.22*cos(arcPhase)'),
            ('waves', 2, 'point_eqs_eel', '0.28*0.72*sin(arcPhase)', '0.22*0.72*sin(arcPhase)'),
            ('waves', 2, 'point_eqs_str', "0.28*Math.cos(a['arcphase'])", "0.22*Math.cos(a['arcphase'])"),
            ('waves', 2, 'point_eqs_str', '0.28*0.72', '0.22*0.72'),
            (
                'shapes',
                1,
                'frame_eqs_eel',
                'angle = instance*2.39996322973 + time*0.025;',
                'angle = instance*2.39996322973 - time*0.10;',
            ),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['angle']=((a['instance']*2.39996322973)+(a['time']*0.025));",
                "a['angle']=((a['instance']*2.39996322973)-(a['time']*0.10));",
            ),
            ('shapes', 1, 'frame_eqs_eel', 'ang = time*0.12 + instance;', 'ang = -time*0.32 + instance;'),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['ang']=((a['time']*0.12)+a['instance']);",
                "a['ang']=((-a['time']*0.32)+a['instance']);",
            ),
            ('shapes', 1, 'frame_eqs_eel', 'r = q9*(1-pick) + q12*pick;', 'r = q15*(1-pick) + q12*pick;'),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['r']=((a['q9']*(1-a['pick']))+(a['q12']*a['pick']));",
                "a['r']=((a['q15']*(1-a['pick']))+(a['q12']*a['pick']));",
            ),
            ('shapes', 1, 'frame_eqs_eel', 'g = q10*(1-pick) + q13*pick;', 'g = q16*(1-pick) + q13*pick;'),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['g']=((a['q10']*(1-a['pick']))+(a['q13']*a['pick']));",
                "a['g']=((a['q16']*(1-a['pick']))+(a['q13']*a['pick']));",
            ),
            ('shapes', 1, 'frame_eqs_eel', 'b = q11*(1-pick) + q14*pick;', 'b = q17*(1-pick) + q14*pick;'),
            (
                'shapes',
                1,
                'frame_eqs_str',
                "a['b']=((a['q11']*(1-a['pick']))+(a['q14']*a['pick']));",
                "a['b']=((a['q17']*(1-a['pick']))+(a['q14']*a['pick']));",
            ),
            ('waves', 3, 'point_eqs_eel', 'impactRadius = 0.12 + q5*0.06;', 'impactRadius = 0.15 + q5*0.08;'),
            (
                'waves',
                3,
                'point_eqs_str',
                "a['impactradius']=(0.12+(a['q5']*0.06));",
                "a['impactradius']=(0.15+(a['q5']*0.08));",
            ),
            ('waves', 3, 'point_eqs_eel', 'time*0.25', 'time*0.38'),
            ('waves', 3, 'point_eqs_str', "(a['time']*0.25)", "(a['time']*0.38)"),
            (
                'waves',
                3,
                'point_eqs_eel',
                'cometPhase = (sample-0.5)*4.2 + time*0.03;',
                'cometPhase = (sample-0.5)*4.2 + time*0.18;',
            ),
            (
                'waves',
                3,
                'point_eqs_str',
                "a['cometphase']=(((a['sample']-0.5)*4.2)+(a['time']*0.03));",
                "a['cometphase']=(((a['sample']-0.5)*4.2)+(a['time']*0.18));",
            ),
            ('waves', 3, 'point_eqs_eel', '0.12*cos(cometPhase)', '0.15*cos(cometPhase)'),
            ('waves', 3, 'point_eqs_str', "0.12*Math.cos(a['cometphase'])", "0.15*Math.cos(a['cometphase'])"),
            ('waves', 3, 'point_eqs_eel', '0.12*0.72*sin(cometPhase)', '0.15*0.72*sin(cometPhase)'),
            (
                'waves',
                3,
                'point_eqs_str',
                "(0.12*0.72)*Math.sin(a['cometphase'])",
                "(0.15*0.72)*Math.sin(a['cometphase'])",
            ),
            ('shapes', 3, 'frame_eqs_eel', 'time*0.03', 'time*0.18'),
            ('shapes', 3, 'frame_eqs_str', "(a['time']*0.03)", "(a['time']*0.18)"),
            ('shapes', 3, 'frame_eqs_eel', '0.12*0.8*cos(angle)', '0.15*0.8*cos(angle)'),
            (
                'shapes',
                3,
                'frame_eqs_str',
                "(0.12*0.8)*Math.cos(a['angle'])",
                "(0.15*0.8)*Math.cos(a['angle'])",
            ),
            ('shapes', 3, 'frame_eqs_eel', '0.12*0.72*0.8*sin(angle)', '0.15*0.72*0.8*sin(angle)'),
            (
                'shapes',
                3,
                'frame_eqs_str',
                "((0.12*0.72)*0.8)*Math.sin(a['angle'])",
                "((0.15*0.72)*0.8)*Math.sin(a['angle'])",
            ),
        ],
    },
}


def replace_once(text: str, old: str, new: str, context: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"{context}: expected one {old!r}, found {count}")
    return text.replace(old, new, 1)


def apply_profile(
    profile: str,
    milk_source: str,
    module_source: str,
) -> tuple[str, str]:
    milk_lines = milk_source.splitlines()
    module_json_start = module_source.find(MODULE_PREFIX)
    module_json_end = module_source.rfind(MODULE_SUFFIX)
    if module_json_start < 0 or module_json_end < 0:
        raise ValueError("generated Butterchurn module wrapper changed")

    preset = json.loads(
        module_source[module_json_start + len(MODULE_PREFIX) : module_json_end]
    )

    if profile == "balanced":
        return milk_source, module_source

    for line_key, old, new in PROFILE_CHANGES[profile]["milk"]:
        matches = [
            i
            for i, line in enumerate(milk_lines)
            if line.startswith(f"{line_key}=")
        ]
        if len(matches) != 1:
            raise ValueError(f"MilkDrop: expected one {line_key}, found {len(matches)}")
        i = matches[0]
        milk_lines[i] = replace_once(milk_lines[i], old, new, f"MilkDrop {line_key}")

    for section, index, field, old, new in PROFILE_CHANGES[profile]["module"]:
        target = preset[section][index]
        target[field] = replace_once(
            target[field],
            old,
            new,
            f"Butterchurn {section}[{index}] {field}",
        )

    milk_output = "\n".join(milk_lines)
    if milk_source.endswith("\n"):
        milk_output += "\n"
    module_output = (
        module_source[: module_json_start + len(MODULE_PREFIX)]
        + json.dumps(preset, indent=2, ensure_ascii=False)
        + MODULE_SUFFIX
    )
    return milk_output, module_output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", choices=("calm", "balanced", "intense"), required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--module", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    milk_source = args.source.read_text()
    module_source = args.module.read_text()
    milk_output, module_output = apply_profile(
        args.profile,
        milk_source,
        module_source,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "royal-mashup-remix.milk").write_text(milk_output)
    (args.output_dir / "royal-mashup-remix.butterchurn.ts").write_text(module_output)


if __name__ == "__main__":
    main()
