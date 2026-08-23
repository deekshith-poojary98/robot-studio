"""Lightweight Robot output.xml statistics extraction.

Not a full parser — prefers the trailing <statistics> block so large logs
do not need a complete XML tree. Per-file suite outcomes use streaming
``iterparse`` so Insights can attribute Project runs without loading the
whole document.
"""

from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

_HEAD_BYTES = 4096
# Large project runs write a multi-MB <statistics> suite table; 256 KiB was
# too small and forced a full-document parse after Robot already exited.
_TAIL_BYTES = 2_097_152
_GENERATOR_RE = re.compile(r'\bgenerator="([^"]*)"')
_FILE_OUTCOMES_NAME = "file_outcomes.json"
_ROBOT_SUFFIXES = (".robot",)


def parse_output_stats(output_xml: Path | None) -> dict:
    """Return total/passed/failed/skipped and robot_version when available."""
    if output_xml is None or not Path(output_xml).is_file():
        return {}

    path = Path(output_xml)
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            head = handle.read(_HEAD_BYTES)
            if size <= _TAIL_BYTES:
                handle.seek(0)
                return _stats_from_document(handle.read(), head)
            handle.seek(max(0, size - _TAIL_BYTES))
            tail = handle.read()
        stats = _stats_from_statistics_tail(head, tail)
        if stats:
            return stats
        return _parse_output_stats_full(path)
    except OSError:
        return {}


def _decode(raw: bytes) -> str:
    return raw.decode("utf-8", errors="ignore")


def _version_from_head(head: bytes) -> str | None:
    match = _GENERATOR_RE.search(_decode(head))
    if match is None:
        return None
    return _generator_version(match.group(1))


def _stats_from_statistics_tail(head: bytes, tail: bytes) -> dict:
    text = _decode(tail)
    start = text.rfind("<statistics")
    end = text.rfind("</statistics>")
    if start < 0 or end < start:
        return {}
    fragment = text[start : end + len("</statistics>")]
    try:
        root = ET.fromstring(fragment)
    except ET.ParseError:
        return {}
    total_el = root.find("./total/stat")
    if total_el is None:
        return {}
    return _totals_from_stat(total_el, _version_from_head(head))


def _stats_from_document(payload: bytes, head: bytes) -> dict:
    try:
        root = ET.fromstring(payload)
    except ET.ParseError:
        return {}
    return _stats_from_root(root, fallback_version=_version_from_head(head))


def _parse_output_stats_full(path: Path) -> dict:
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return {}
    return _stats_from_root(root)


def _stats_from_root(
    root: ET.Element,
    fallback_version: str | None = None,
) -> dict:
    robot_version = _generator_version(root.attrib.get("generator", "")) or fallback_version
    total_el = root.find("./statistics/total/stat")
    if total_el is not None:
        return _totals_from_stat(total_el, robot_version)

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


def _totals_from_stat(total_el: ET.Element, robot_version: str | None) -> dict:
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


def parse_file_suite_outcomes(output_xml: Path | None) -> dict[str, str]:
    """Map leaf ``.robot`` suite ``source`` → PASS|FAIL|SKIP.

    Streams the document so multi-thousand-file project runs stay usable.
    Nested folder suites (no ``.robot`` suffix) are ignored.
    """
    if output_xml is None or not Path(output_xml).is_file():
        return {}

    outcomes: dict[str, str] = {}
    try:
        for _event, elem in ET.iterparse(Path(output_xml), events=("end",)):
            if elem.tag != "suite":
                continue
            source = (elem.attrib.get("source") or "").strip()
            if not source.lower().endswith(_ROBOT_SUFFIXES):
                elem.clear()
                continue
            status_el = elem.find("status")
            status = (
                (status_el.attrib.get("status") if status_el is not None else "") or ""
            ).upper()
            if status:
                outcomes[source.replace("\\", "/")] = status
            elem.clear()
    except (ET.ParseError, OSError):
        return {}
    return outcomes


def file_outcomes_sidecar_path(output_dir: Path | None) -> Path | None:
    if output_dir is None:
        return None
    root = Path(output_dir)
    if not root.is_dir():
        return None
    return root / _FILE_OUTCOMES_NAME


def write_file_outcomes_sidecar(
    output_dir: Path | None,
    outcomes: dict[str, str],
) -> Path | None:
    """Persist per-file suite outcomes next to output.xml for Insights."""
    path = file_outcomes_sidecar_path(output_dir)
    if path is None or not outcomes:
        return None
    try:
        path.write_text(
            json.dumps({"files": outcomes}, indent=0, sort_keys=True),
            encoding="utf-8",
        )
    except OSError:
        return None
    return path


def load_cached_file_outcomes(output_dir: Path | None) -> dict[str, str]:
    """Read ``file_outcomes.json`` only — never parse ``output.xml``."""
    if output_dir is None:
        return {}
    sidecar = file_outcomes_sidecar_path(Path(output_dir))
    if sidecar is None or not sidecar.is_file():
        return {}
    try:
        payload = json.loads(sidecar.read_text(encoding="utf-8"))
        files = payload.get("files") if isinstance(payload, dict) else None
        if isinstance(files, dict):
            return {
                str(key).replace("\\", "/"): str(value).upper()
                for key, value in files.items()
                if str(key).strip()
            }
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        pass
    return {}


def load_or_build_file_outcomes(output_dir: Path | None) -> dict[str, str]:
    """Read ``file_outcomes.json``, or build it once from output.xml."""
    cached = load_cached_file_outcomes(output_dir)
    if cached:
        return cached
    if output_dir is None:
        return {}
    root = Path(output_dir)
    xml_path = root / "output.xml"
    outcomes = parse_file_suite_outcomes(xml_path if xml_path.is_file() else None)
    if outcomes:
        write_file_outcomes_sidecar(root, outcomes)
    return outcomes
