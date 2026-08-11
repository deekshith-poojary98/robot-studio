"""Unit tests for typed execution-plan → Robot argv."""

from pathlib import Path
from uuid import uuid4

import pytest

from robot_studio.application.services.execution_plan import (
    ExecutionPlan,
    ExecutionPlanError,
    config_to_robot_args,
    plan_to_robot_args,
    resolve_variable_files,
    validate_extra_robot_args,
)
from robot_studio.domain.models import Environment
from robot_studio.domain.models.run_configuration import RunVariable


def test_config_to_robot_args_structured_fields() -> None:
    args = config_to_robot_args(
        include_tags=["smoke", "critical"],
        exclude_tags=["wip"],
        variables=[
            RunVariable(key="ENV", value="staging"),
            RunVariable(key="BROWSER", value="chrome"),
        ],
        variable_files=["/tmp/proj/config/staging.py"],
        extra_robot_args=["--loglevel", "DEBUG"],
    )
    assert args == [
        "--include",
        "smoke",
        "--include",
        "critical",
        "--exclude",
        "wip",
        "--variable",
        "ENV:staging",
        "--variable",
        "BROWSER:chrome",
        "--variablefile",
        "/tmp/proj/config/staging.py",
        "--loglevel",
        "DEBUG",
    ]


def test_plan_merges_config_then_target_args() -> None:
    env = Environment(
        id=uuid4(),
        workspace_id=uuid4(),
        name="venv",
        path=Path("/tmp/venv"),
        python_version="3.12",
        python_executable=Path("/tmp/venv/bin/python"),
        pip_executable=Path("/tmp/venv/bin/pip"),
        created_at=__import__("datetime").datetime.now(
            __import__("datetime").UTC,
        ),
    )
    plan = ExecutionPlan(
        suite="/tmp/proj/login.robot",
        environment=env,
        include_tags=["smoke"],
        target_robot_args=["--test", "Login"],
        configuration_name="Smoke - Staging",
    )
    assert plan_to_robot_args(plan) == [
        "--include",
        "smoke",
        "--test",
        "Login",
    ]


@pytest.mark.parametrize(
    "args",
    [
        ["--outputdir", "/tmp"],
        ["-d", "/tmp"],
        ["--listener", "x.py"],
        ["--listener=x.py"],
        ["--outputdir=/tmp"],
        ["--output", "x.xml"],
        ["--log", "x.html"],
        ["--report", "x.html"],
        ["suite.robot"],
    ],
)
def test_validate_rejects_studio_owned_args(args: list[str]) -> None:
    with pytest.raises(ExecutionPlanError) as exc:
        validate_extra_robot_args(args)
    assert exc.value.code == "invalid_robot_args"


def test_variable_file_must_exist_inside_project(tmp_path: Path) -> None:
    project = tmp_path / "proj"
    project.mkdir()
    nested = project / "config"
    nested.mkdir()
    target = nested / "staging.py"
    target.write_text("ENV = 'qa'\n", encoding="utf-8")

    resolved = resolve_variable_files(project, ["config/staging.py"])
    assert resolved == [str(target.resolve())]

    with pytest.raises(ExecutionPlanError) as missing:
        resolve_variable_files(project, ["config/missing.py"])
    assert missing.value.code == "variable_file_missing"

    outside = tmp_path / "other.py"
    outside.write_text("x = 1\n", encoding="utf-8")
    with pytest.raises(ExecutionPlanError) as escaped:
        resolve_variable_files(project, [str(outside)])
    assert escaped.value.code == "variable_file_missing"


def test_variable_key_rejects_colon() -> None:
    with pytest.raises(ExecutionPlanError):
        config_to_robot_args(
            include_tags=[],
            exclude_tags=[],
            variables=[RunVariable(key="ENV:staging", value="x")],
            variable_files=[],
            extra_robot_args=[],
        )
