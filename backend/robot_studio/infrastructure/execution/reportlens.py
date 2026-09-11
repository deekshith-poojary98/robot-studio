"""On-demand ReportLens HTML generation from Robot Framework output.xml."""

from __future__ import annotations

from pathlib import Path


REPORTLENS_HTML_NAME = "reportlens.html"


def generate_reportlens_html(output_xml: Path, output_html: Path) -> Path:
    """Build a self-contained ReportLens HTML report next to ``output.xml``.

    Uses self-contained mode (no ``--external-data``) so the OS default
    browser can open the file via ``file://`` without a local web server.
    """
    from robotframework_reportlens.generator import RobotFrameworkReportGenerator

    xml_path = Path(output_xml)
    html_path = Path(output_html)
    if not xml_path.is_file():
        raise FileNotFoundError(f"output.xml not found: {xml_path}")
    html_path.parent.mkdir(parents=True, exist_ok=True)
    generator = RobotFrameworkReportGenerator(
        str(xml_path),
        external_data=False,
    )
    generator.generate_html(str(html_path), external_data=False)
    if not html_path.is_file():
        raise RuntimeError(f"ReportLens did not write {html_path}")
    return html_path


def reportlens_needs_rebuild(output_xml: Path, output_html: Path) -> bool:
    """True when ReportLens HTML is missing or older than ``output.xml``."""
    xml_path = Path(output_xml)
    html_path = Path(output_html)
    if not html_path.is_file():
        return True
    if not xml_path.is_file():
        return False
    return html_path.stat().st_mtime < xml_path.stat().st_mtime
