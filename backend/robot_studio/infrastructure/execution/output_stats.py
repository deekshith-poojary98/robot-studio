"""Lightweight Robot output.xml statistics extraction.

Not a full parser — only reads aggregate totals and generator version.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from pathlib import Path


def parse_output_stats(output_xml: Path | None) -> dict:
    """Return total/passed/failed/skipped and robot_version when available."""
    if output_xml is None or not Path(output_xml).is_file():
        return {}

    try:
        root = ET.parse(Path(output_xml)).getroot()
    except (ET.ParseError, OSError):
        return {}

    robot_version = _generator_version(root.attrib.get("generator", ""))

    total_el = root.find("./statistics/total/stat")
    if total_el is not None:
        passed = _int_attr(total_el, "pass")
        failed = _int_attr(total_el, "fail")
        skipped = _int_attr(total_el, "skip")
        return {
            "total_tests": passed + failed + skipped,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "robot_version": robot_version,
        }

    # Fallback: count test nodes.
    tests = root.findall(".//test")
    passed = failed = skipped = 0
    for test in tests:
        status = test.find("status")
        if status is None:
            continue
        value = (status.attrib.get("status") or "").upper()
        if value == "PASS":
            passed += 1
        elif value == "FAIL":
            failed += 1
        elif value == "SKIP":
            skipped += 1
    if not tests:
        return {"robot_version": robot_version} if robot_version else {}
    return {
        "total_tests": passed + failed + skipped,
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "robot_version": robot_version,
    }


def _generator_version(generator: str) -> str | None:
    # e.g. "Robot 7.0.1 (Python 3.12.0 on darwin)"
    if not generator.startswith("Robot "):
        return None
    parts = generator.split()
    if len(parts) < 2:
        return None
    return parts[1]


def _int_attr(element: ET.Element, name: str) -> int:
    try:
        return int(element.attrib.get(name, "0") or "0")
    except ValueError:
        return 0


def parse_test_results(output_xml: Path | None) -> list[dict]:
    """Return per-test results from output.xml (name, status, source, message)."""
    if output_xml is None or not Path(output_xml).is_file():
        return []

    try:
        root = ET.parse(Path(output_xml)).getroot()
    except (ET.ParseError, OSError):
        return []

    results: list[dict] = []
    for suite in root.iter("suite"):
        source = suite.attrib.get("source") or ""
        for test in suite.findall("test"):
            name = test.attrib.get("name") or ""
            if not name:
                continue
            status_el = test.find("status")
            status = (status_el.attrib.get("status") if status_el is not None else "") or ""
            message = ""
            if status_el is not None and status_el.text:
                message = status_el.text.strip()
            results.append(
                {
                    "name": name,
                    "status": status.upper(),
                    "source": source,
                    "message": message,
                },
            )
    return results


def list_failed_tests(output_xml: Path | None) -> list[dict]:
    return [
        item
        for item in parse_test_results(output_xml)
        if item.get("status") == "FAIL"
    ]
