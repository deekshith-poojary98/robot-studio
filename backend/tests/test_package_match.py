"""Unit tests for deterministic package match ranking."""

from __future__ import annotations

from robot_studio.domain.models import InstalledPackage, PackageSearchResult
from robot_studio.infrastructure.packages.package_match import (
    normalize_package_name,
    package_match_key,
    rank_packages,
)


def _pkg(name: str, summary: str | None = None) -> InstalledPackage:
    return InstalledPackage(
        name=name,
        version="1.0.0",
        summary=summary,
    )


def test_normalize_collapses_separators() -> None:
    assert normalize_package_name("Robot_Framework") == "robot-framework"
    assert normalize_package_name("robot.framework") == "robot-framework"
    assert normalize_package_name("  Robot--Framework  ") == "robot-framework"


def test_tiers_exact_prefix_substring() -> None:
    exact = package_match_key("Requests", "requests")
    prefix = package_match_key("robot", "robotframework")
    substring = package_match_key("framework", "robotframework")
    assert exact is not None and exact[0] == 0
    assert prefix is not None and prefix[0] == 1
    assert substring is not None and substring[0] == 2


def test_no_fuzzy_subsequence_match() -> None:
    assert package_match_key("rflib", "robotframework-library") is None
    assert package_match_key("rf", "robotframework") is None
    assert package_match_key("ws", "trio-websocket") is None
    assert package_match_key("pan", "pydantic") is None
    assert package_match_key("pan", "paginate") is None


def test_no_summary_match() -> None:
    assert (
        package_match_key(
            "pan",
            "bracex",
            summary="Bash style brace expander.",
        )
        is None
    )
    packages = [
        _pkg("helper-utils", summary="HTTP client for robot"),
        _pkg("robotframework"),
        _pkg("other"),
    ]
    ranked = rank_packages(packages, "robot")
    assert [item.name for item in ranked] == ["robotframework"]


def test_substring_still_matches_contiguous_name() -> None:
    mid = package_match_key("lph", "alpha")
    assert mid is not None and mid[0] == 2
    assert package_match_key("pan", "paginate") is None  # "pan" not contiguous
    assert package_match_key("agi", "paginate") is not None


def test_rank_order_is_deterministic() -> None:
    packages = [
        _pkg("robotframework-seleniumlibrary"),
        _pkg("robotframework"),
        _pkg("awesome-robot-tools"),
        _pkg("rbt"),
        _pkg("unrelated"),
    ]
    ranked = rank_packages(packages, "robot")
    names = [item.name for item in ranked]
    assert names[0] == "robotframework"  # prefix beats substring
    assert "robotframework-seleniumlibrary" in names  # substring
    assert "awesome-robot-tools" in names  # substring
    assert "rbt" not in names  # fuzzy no longer matches
    assert "unrelated" not in names
    assert [item.name for item in rank_packages(packages, "robot")] == names


def test_rank_packages_accepts_search_results() -> None:
    results = [
        PackageSearchResult(name="zzz-robot", latest_version="1", summary=None),
        PackageSearchResult(name="robot", latest_version="2", summary=None),
        PackageSearchResult(name="robotframework", latest_version="3", summary=None),
    ]
    ranked = rank_packages(results, "robot")
    assert [item.name for item in ranked] == [
        "robot",
        "robotframework",
        "zzz-robot",
    ]
