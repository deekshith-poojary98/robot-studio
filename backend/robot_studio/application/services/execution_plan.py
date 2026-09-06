"""Typed execution plan → Robot argv.

Widgets never build CLI strings. Only ExecutionService starts Robot.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID

from robot_studio.domain.models import Environment
from robot_studio.domain.models.run_configuration import RunVariable

#: Flags owned by SubprocessRunner — extra args must not override these.
#: ``--listener`` is allowed so projects can add their own listeners; Studio
#: always prepends its progress listener first (see SubprocessRunner.start).
STUDIO_OWNED_FLAGS = frozenset(
    {
        "--outputdir",
        "-d",
        "--output",
        "-o",
        "--log",
        "-l",
        "--report",
        "-r",
    },
)

_VALUE_FLAGS_ALLOWING_ROBOT_PATH = frozenset(
    {
        "--variablefile",
        "-V",
        "--pythonpath",
        "-P",
        "--extension",
        "--prerunmodifier",
        "--parser",
    },
)


class ExecutionPlanError(Exception):
    def __init__(self, message: str, *, code: str | None = None) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class ExecutionPlan:
    """Target + configuration, ready for ExecutionService._start_run."""

    suite: str
    environment: Environment
    include_tags: list[str] = field(default_factory=list)
    exclude_tags: list[str] = field(default_factory=list)
    variables: list[RunVariable] = field(default_factory=list)
    variable_files: list[str] = field(default_factory=list)
    extra_robot_args: list[str] = field(default_factory=list)
    target_robot_args: list[str] = field(default_factory=list)
    configuration_id: UUID | None = None
    configuration_name: str | None = None
    run_label: str | None = None


def validate_extra_robot_args(args: list[str]) -> None:
    """Reject Studio-owned flags and extra suite/target paths."""
    previous_flag = ""
    for raw in args:
        tok = str(raw).strip()
        if not tok:
            raise ExecutionPlanError(
                "Advanced Robot arguments cannot include empty tokens.",
                code="invalid_robot_args",
            )
        # One argv token per row — ``--listener pkg.Class`` as a single cell
        # becomes one unknown Robot option (spaces included).
        if tok.startswith("-") and " " in tok and "=" not in tok.split(" ", 1)[0]:
            flag_guess = tok.split(" ", 1)[0]
            raise ExecutionPlanError(
                f"Put '{flag_guess}' and its value on separate rows "
                "(one argv token per row), not in a single cell.",
                code="invalid_robot_args",
            )
        flag = tok.split("=", 1)[0]
        if flag in STUDIO_OWNED_FLAGS:
            raise ExecutionPlanError(
                f"Advanced arguments cannot override Studio-owned option '{flag}'.",
                code="invalid_robot_args",
            )
        looks_like_suite = tok.lower().endswith((".robot", ".resource"))
        if (
            looks_like_suite
            and previous_flag not in _VALUE_FLAGS_ALLOWING_ROBOT_PATH
            and not tok.startswith("-")
        ):
            raise ExecutionPlanError(
                    "Advanced arguments cannot set the suite or target path.",
                    code="invalid_robot_args",
                )
        previous_flag = flag if tok.startswith("-") and "=" not in tok else ""


def config_to_robot_args(
    *,
    include_tags: list[str],
    exclude_tags: list[str],
    variables: list[RunVariable],
    variable_files: list[str],
    extra_robot_args: list[str],
) -> list[str]:
    """Translate structured configuration fields into Robot argv tokens."""
    validate_extra_robot_args(extra_robot_args)
    args: list[str] = []
    for tag in include_tags:
        cleaned = tag.strip()
        if cleaned:
            args.extend(["--include", cleaned])
    for tag in exclude_tags:
        cleaned = tag.strip()
        if cleaned:
            args.extend(["--exclude", cleaned])
    for item in variables:
        key = item.key.strip()
        if not key:
            continue
        if ":" in key:
            raise ExecutionPlanError(
                f"Variable name cannot contain ':': '{key}'",
                code="invalid_variable",
            )
        args.extend(["--variable", f"{key}:{item.value}"])
    for path in variable_files:
        cleaned = str(path).strip()
        if cleaned:
            args.extend(["--variablefile", cleaned])
    args.extend(str(tok).strip() for tok in extra_robot_args if str(tok).strip())
    return args


def plan_to_robot_args(plan: ExecutionPlan) -> list[str]:
    config_args = config_to_robot_args(
        include_tags=plan.include_tags,
        exclude_tags=plan.exclude_tags,
        variables=plan.variables,
        variable_files=plan.variable_files,
        extra_robot_args=plan.extra_robot_args,
    )
    target = [str(tok) for tok in plan.target_robot_args if str(tok).strip()]
    return [*config_args, *target]


def resolve_variable_files(project_path: Path, relative_paths: list[str]) -> list[str]:
    """Resolve project-relative variable files; reject missing or escaped paths."""
    root = project_path.expanduser().resolve()
    resolved: list[str] = []
    for raw in relative_paths:
        cleaned = str(raw).strip()
        if not cleaned:
            continue
        candidate = Path(cleaned).expanduser()
        if not candidate.is_absolute():
            candidate = (root / candidate).resolve()
        else:
            candidate = candidate.resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise ExecutionPlanError(
                f"Variable file must be inside the project: '{cleaned}'",
                code="variable_file_missing",
            ) from exc
        if not candidate.is_file():
            raise ExecutionPlanError(
                f"Variable file not found: '{cleaned}'",
                code="variable_file_missing",
            )
        resolved.append(str(candidate))
    return resolved
