"""Parse Robot Framework output.xml into an execution trace for linking."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from xml.etree import ElementTree as ET


@dataclass
class KeywordStep:
    name: str
    owner: str = ""
    status: str = "PASS"
    elapsed_ms: float = 0.0
    children: list[KeywordStep] = field(default_factory=list)


@dataclass
class TestTrace:
    name: str
    status: str
    elapsed_ms: float
    source: str
    line: int | None = None
    message: str = ""
    keywords: list[KeywordStep] = field(default_factory=list)


@dataclass
class SuiteTrace:
    name: str
    source: str
    status: str
    elapsed_ms: float
    tests: list[TestTrace] = field(default_factory=list)
    suites: list[SuiteTrace] = field(default_factory=list)


@dataclass
class ExecutionTrace:
    suites: list[SuiteTrace]
    robot_version: str | None = None


def _elapsed_ms(status_el: ET.Element | None) -> float:
    if status_el is None:
        return 0.0
    raw = status_el.attrib.get("elapsed")
    if raw is not None:
        try:
            return float(raw) * 1000.0
        except ValueError:
            return 0.0
    # Legacy: end - start if present as ISO — skip; prefer elapsed
    return 0.0


def _status(status_el: ET.Element | None) -> str:
    if status_el is None:
        return ""
    return (status_el.attrib.get("status") or "").upper()


def _message(status_el: ET.Element | None) -> str:
    if status_el is None or not status_el.text:
        return ""
    return status_el.text.strip()


def _parse_keyword(kw_el: ET.Element) -> KeywordStep:
    status_el = kw_el.find("status")
    children = [_parse_keyword(child) for child in kw_el.findall("kw")]
    return KeywordStep(
        name=kw_el.attrib.get("name") or "",
        owner=kw_el.attrib.get("owner") or "",
        status=_status(status_el),
        elapsed_ms=_elapsed_ms(status_el),
        children=children,
    )


def _parse_test(test_el: ET.Element, suite_source: str) -> TestTrace:
    status_el = test_el.find("status")
    line_raw = test_el.attrib.get("line")
    line = int(line_raw) if line_raw and line_raw.isdigit() else None
    return TestTrace(
        name=test_el.attrib.get("name") or "",
        status=_status(status_el),
        elapsed_ms=_elapsed_ms(status_el),
        source=suite_source,
        line=line,
        message=_message(status_el),
        keywords=[_parse_keyword(kw) for kw in test_el.findall("kw")],
    )


def _parse_suite(suite_el: ET.Element) -> SuiteTrace:
    source = suite_el.attrib.get("source") or ""
    status_el = suite_el.find("status")
    return SuiteTrace(
        name=suite_el.attrib.get("name") or "",
        source=source,
        status=_status(status_el),
        elapsed_ms=_elapsed_ms(status_el),
        tests=[_parse_test(t, source) for t in suite_el.findall("test")],
        suites=[_parse_suite(s) for s in suite_el.findall("suite")],
    )


def parse_execution_trace(output_xml: Path | None) -> ExecutionTrace | None:
    """Full suite/test/keyword tree from output.xml (RF 5+ schema)."""
    if output_xml is None or not Path(output_xml).is_file():
        return None
    try:
        root = ET.parse(Path(output_xml)).getroot()
    except (ET.ParseError, OSError):
        return None

    generator = root.attrib.get("generator", "")
    robot_version = None
    if generator.startswith("Robot "):
        parts = generator.split()
        if len(parts) >= 2:
            robot_version = parts[1]

    suites = [_parse_suite(s) for s in root.findall("suite")]
    return ExecutionTrace(suites=suites, robot_version=robot_version)


def flatten_keyword_steps(steps: list[KeywordStep]) -> list[KeywordStep]:
    """Depth-first flatten including nested keyword calls."""
    out: list[KeywordStep] = []

    def walk(step: KeywordStep) -> None:
        out.append(step)
        for child in step.children:
            walk(child)

    for step in steps:
        walk(step)
    return out


def iter_tests(trace: ExecutionTrace) -> list[tuple[SuiteTrace, TestTrace]]:
    pairs: list[tuple[SuiteTrace, TestTrace]] = []

    def walk(suite: SuiteTrace) -> None:
        for test in suite.tests:
            pairs.append((suite, test))
        for child in suite.suites:
            walk(child)

    for suite in trace.suites:
        walk(suite)
    return pairs
