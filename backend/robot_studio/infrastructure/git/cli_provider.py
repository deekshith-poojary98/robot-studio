"""Git CLI provider — invokes native git via subprocess."""

from __future__ import annotations

import logging
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

from robot_studio.domain.interfaces.git import GitProvider
from robot_studio.domain.models.git import (
    GitBranch,
    GitCommit,
    GitCommitDetail,
    GitDiff,
    GitDiffLine,
    GitFileChange,
    GitFileStatus,
    GitIdentity,
    GitRemote,
    GitRemoteResult,
    GitRepositoryInfo,
    GitStatus,
)
from robot_studio.infrastructure.process_utils import run_blocking, windows_no_window_kwargs

logger = logging.getLogger(__name__)


class GitCommandError(Exception):
    """Raised when a git command fails."""


def git_missing_message() -> str:
    """How to install Git on this OS — used when ``git`` is not on PATH."""
    if sys.platform == "win32":
        return (
            "Git is not installed or not on PATH. "
            "Install Git for Windows, then restart Robot Studio."
        )
    if sys.platform == "darwin":
        return (
            "Git is not installed or not on PATH. "
            "Install Git (xcode-select --install, or brew install git), "
            "then restart Robot Studio."
        )
    return (
        "Git is not installed or not on PATH. "
        "Install it (e.g. sudo apt install git), then restart Robot Studio."
    )


class CliGitProvider(GitProvider):
    def __init__(self, *, timeout: float = 120.0) -> None:
        self._timeout = timeout

    async def detect(self, path: Path) -> GitRepositoryInfo | None:
        """Detect a Git repo scoped to *path* (usually the active project).

        Never silently attach to an unrelated parent monorepo: if ``git`` reports
        a toplevel that is a strict ancestor of *path*, treat the project as
        not-a-repository so the user can Init inside the project (or open the
        parent folder explicitly as the project).
        """
        target = path.resolve()
        if not target.exists():
            return None
        # Prefer a .git that lives on the scoped path itself.
        if (target / ".git").exists():
            return await self._repository_info(target)
        try:
            root = await self._run_text(["rev-parse", "--show-toplevel"], cwd=target)
        except GitCommandError:
            return None
        root_path = Path(root.strip()).resolve()
        if root_path == target:
            return await self._repository_info(root_path)
        # Project nested inside another repo (parent monorepo) — do not claim it.
        try:
            target.relative_to(root_path)
        except ValueError:
            return None
        return None


    async def init(self, path: Path) -> GitRepositoryInfo:
        target = path.resolve()
        await self._run(["init"], cwd=target)
        return await self._repository_info(target)

    async def status(self, repo_root: Path) -> GitStatus:
        repository = await self._repository_info(repo_root, include_porcelain=False)
        # -uall: list files inside untracked dirs (IDE-friendly). Ignored paths
        # still stay hidden via .gitignore.
        raw = await self._run_text(
            ["status", "--porcelain=v1", "-uall"],
            cwd=repo_root,
        )
        changes = _parse_porcelain(raw)
        repository.clean = len(changes) == 0
        return GitStatus(repository=repository, changes=changes)

    async def history(self, repo_root: Path, *, limit: int = 50) -> list[GitCommit]:
        try:
            output = await self._run_text(
                [
                    "log",
                    f"-{limit}",
                    "--format=%H%x00%an%x00%ae%x00%at%x00%s",
                ],
                cwd=repo_root,
            )
        except GitCommandError as exc:
            if "does not have any commits yet" in str(exc):
                return []
            raise
        commits: list[GitCommit] = []
        for line in output.splitlines():
            if not line.strip():
                continue
            parts = line.split("\0")
            if len(parts) < 5:
                continue
            commit_hash, author, email, ts_raw, message = parts[:5]
            commits.append(
                GitCommit(
                    hash=commit_hash,
                    short_hash=commit_hash[:7],
                    author=author,
                    email=email,
                    date=datetime.fromtimestamp(int(ts_raw), tz=UTC),
                    message=message,
                ),
            )
        return commits

    async def commit_detail(self, repo_root: Path, commit_hash: str) -> GitCommitDetail:
        output = await self._run_text(
            [
                "show",
                "--name-status",
                "--format=%H%x00%an%x00%ae%x00%at%x00%s",
                commit_hash,
            ],
            cwd=repo_root,
        )
        lines = output.splitlines()
        if not lines:
            raise GitCommandError(f"Commit not found: {commit_hash}")
        header = lines[0].split("\0")
        if len(header) < 5:
            raise GitCommandError(f"Invalid commit header for {commit_hash}")
        commit = GitCommit(
            hash=header[0],
            short_hash=header[0][:7],
            author=header[1],
            email=header[2],
            date=datetime.fromtimestamp(int(header[3]), tz=UTC),
            message=header[4],
        )
        files: list[GitFileChange] = []
        for row in lines[1:]:
            row = row.strip()
            if not row:
                continue
            parts = row.split("\t")
            if len(parts) == 2:
                code, file_path = parts
                files.append(_name_status_to_change(code, file_path))
            elif len(parts) == 3:
                code, old_path, new_path = parts
                files.append(
                    GitFileChange(
                        path=new_path,
                        old_path=old_path,
                        status=_code_to_status(code),
                    ),
                )
        return GitCommitDetail(**commit.model_dump(), files=files)

    async def branches(self, repo_root: Path) -> list[GitBranch]:
        output = await self._run_text(
            ["branch", "-a", "--format=%(refname:short)|%(HEAD)|%(upstream:short)"],
            cwd=repo_root,
        )
        branches: list[GitBranch] = []
        for line in output.splitlines():
            if not line.strip():
                continue
            name, head, _upstream = (line.split("|") + ["", ""])[:3]
            branches.append(
                GitBranch(
                    name=name,
                    current=head == "*",
                    remote=name.startswith("origin/") or "/" in name,
                ),
            )
        if not branches:
            try:
                current = (
                    await self._run_text(["symbolic-ref", "--short", "HEAD"], cwd=repo_root)
                ).strip()
                if current and current != "HEAD":
                    branches.append(GitBranch(name=current, current=True, remote=False))
            except GitCommandError:
                pass
        return branches

    async def checkout(self, repo_root: Path, branch: str) -> GitRepositoryInfo:
        try:
            current = (
                await self._run_text(["symbolic-ref", "--short", "HEAD"], cwd=repo_root)
            ).strip()
            if current == branch:
                return await self._repository_info(repo_root)
        except GitCommandError:
            pass
        await self._run(["checkout", branch], cwd=repo_root)
        return await self._repository_info(repo_root)

    async def create_branch(
        self,
        repo_root: Path,
        name: str,
        *,
        start_point: str | None = None,
    ) -> GitBranch:
        if start_point is None and not await self._has_head(repo_root):
            await self._run(["checkout", "-b", name], cwd=repo_root)
            return GitBranch(name=name, current=True, remote=False)
        args = ["branch", name]
        if start_point:
            args.append(start_point)
        await self._run(args, cwd=repo_root)
        return GitBranch(name=name, current=False, remote=False)

    async def delete_branch(self, repo_root: Path, name: str) -> None:
        await self._run(["branch", "-d", name], cwd=repo_root)

    async def commit(
        self,
        repo_root: Path,
        message: str,
        *,
        files: list[str] | None = None,
    ) -> GitCommit:
        identity = await self.get_identity(repo_root)
        if not identity.is_complete:
            raise GitCommandError(
                "Git identity is not configured. Set your name and email before committing.",
            )
        if files:
            await self._run(["add", "--", *files], cwd=repo_root)
        else:
            await self._run(["add", "-A"], cwd=repo_root)
        await self._run(["commit", "-m", message], cwd=repo_root)
        history = await self.history(repo_root, limit=1)
        if not history:
            raise GitCommandError("Commit succeeded but history is empty")
        return history[0]

    async def fetch(self, repo_root: Path) -> GitRemoteResult:
        try:
            output = await self._run_text(["fetch", "--all", "--prune"], cwd=repo_root)
            return GitRemoteResult(success=True, message="Fetch completed", output=output)
        except GitCommandError as exc:
            return GitRemoteResult(success=False, message=str(exc), output=str(exc))

    async def pull(self, repo_root: Path) -> GitRemoteResult:
        try:
            output = await self._run_text(["pull"], cwd=repo_root)
            return GitRemoteResult(success=True, message="Pull completed", output=output)
        except GitCommandError as exc:
            return GitRemoteResult(success=False, message=str(exc), output=str(exc))

    async def push(self, repo_root: Path) -> GitRemoteResult:
        remotes = await self.list_remotes(repo_root)
        if not remotes:
            return GitRemoteResult(
                success=False,
                message="No remote configured. Add a remote URL before pushing.",
            )
        try:
            output = await self._run_text(["push"], cwd=repo_root)
            return GitRemoteResult(success=True, message="Push completed", output=output)
        except GitCommandError as first_error:
            # First push often needs an upstream. Prefer origin when present.
            remote_name = next(
                (item.name for item in remotes if item.name == "origin"),
                remotes[0].name,
            )
            try:
                output = await self._run_text(
                    ["push", "-u", remote_name, "HEAD"],
                    cwd=repo_root,
                )
                return GitRemoteResult(
                    success=True,
                    message=f"Push completed (set upstream to {remote_name})",
                    output=output,
                )
            except GitCommandError:
                return GitRemoteResult(
                    success=False,
                    message=str(first_error),
                    output=str(first_error),
                )

    async def list_remotes(self, repo_root: Path) -> list[GitRemote]:
        try:
            raw = await self._run_text(["remote", "-v"], cwd=repo_root)
        except GitCommandError:
            return []
        return _parse_remotes(raw)

    async def add_remote(
        self,
        repo_root: Path,
        *,
        name: str,
        url: str,
    ) -> list[GitRemote]:
        remote_name = name.strip() or "origin"
        remote_url = url.strip()
        if not remote_url:
            raise GitCommandError("Remote URL is required")
        existing = {item.name for item in await self.list_remotes(repo_root)}
        if remote_name in existing:
            await self._run(["remote", "set-url", remote_name, remote_url], cwd=repo_root)
        else:
            await self._run(["remote", "add", remote_name, remote_url], cwd=repo_root)
        return await self.list_remotes(repo_root)

    async def seed_local_remote(
        self,
        repo_root: Path,
        *,
        relative_path: str = ".test-remotes/origin.git",
        remote_name: str = "origin",
    ) -> str:
        """Create a bare remote under the repo and set upstream tracking."""
        remote_path = (repo_root / relative_path).resolve()
        if remote_path.exists():
            shutil.rmtree(remote_path)
        remote_path.mkdir(parents=True, exist_ok=True)
        await self._run(["init", "--bare"], cwd=remote_path)

        # Replace existing remote if present.
        try:
            await self._run(["remote", "remove", remote_name], cwd=repo_root)
        except GitCommandError:
            pass
        await self._run(
            ["remote", "add", remote_name, str(remote_path)],
            cwd=repo_root,
        )

        branch = (
            await self._run_text(["rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_root)
        ).strip()
        if branch and branch != "HEAD":
            await self._run(
                ["config", f"branch.{branch}.remote", remote_name],
                cwd=repo_root,
            )
            await self._run(
                ["config", f"branch.{branch}.merge", f"refs/heads/{branch}"],
                cwd=repo_root,
            )
        return str(remote_path)

    async def diff(
        self,
        repo_root: Path,
        *,
        file_path: str | None = None,
        commit: str | None = None,
    ) -> GitDiff:
        args = ["diff", "--no-color"]
        if commit:
            args.append(commit)
        if file_path:
            args.extend(["--", file_path])
        output = await self._run_text(args, cwd=repo_root)
        return _parse_unified_diff(output, file_path)

    async def _has_head(self, repo_root: Path) -> bool:
        try:
            await self._run_text(["rev-parse", "HEAD"], cwd=repo_root)
            return True
        except GitCommandError:
            return False

    async def _repository_info(
        self,
        repo_root: Path,
        *,
        include_porcelain: bool = True,
    ) -> GitRepositoryInfo:
        head: str | None = None
        try:
            head = (await self._run_text(["rev-parse", "HEAD"], cwd=repo_root)).strip()
        except GitCommandError:
            head = None
        detached = False
        branch: str | None
        try:
            branch = (
                await self._run_text(["rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_root)
            ).strip()
            if branch == "HEAD":
                detached = True
                branch = None
        except GitCommandError:
            detached = head is None
            branch = None
            try:
                branch = (
                    await self._run_text(["symbolic-ref", "--short", "HEAD"], cwd=repo_root)
                ).strip()
            except GitCommandError:
                pass
        clean = True
        if include_porcelain:
            status_raw = await self._run_text(
                ["status", "--porcelain=v1", "-uall"],
                cwd=repo_root,
            )
            changes = _parse_porcelain(status_raw)
            clean = len(changes) == 0
        remotes = await self.list_remotes(repo_root)
        return GitRepositoryInfo(
            is_repository=True,
            root=repo_root,
            branch=branch,
            head=head if head else None,
            detached=detached,
            clean=clean,
            remotes=remotes,
            identity=await self.get_identity(repo_root),
        )

    async def get_identity(self, repo_root: Path) -> GitIdentity:
        local_name = await self._config_scoped(repo_root, "user.name", scope="local")
        local_email = await self._config_scoped(repo_root, "user.email", scope="local")
        global_name = await self._config_scoped(repo_root, "user.name", scope="global")
        global_email = await self._config_scoped(repo_root, "user.email", scope="global")
        name = local_name or global_name or ""
        email = local_email or global_email or ""
        if local_name or local_email:
            source = "local"
        elif global_name or global_email:
            source = "global"
        else:
            source = "unset"
        return GitIdentity(name=name, email=email, source=source)

    async def set_identity(
        self,
        repo_root: Path,
        *,
        name: str,
        email: str,
        scope: str,
    ) -> GitIdentity:
        use_global = scope == "global"
        flag = "--global" if use_global else "--local"
        if use_global:
            await self._unset_local_identity(repo_root)
        await self._run(["config", flag, "user.name", name], cwd=repo_root)
        await self._run(["config", flag, "user.email", email], cwd=repo_root)
        return await self.get_identity(repo_root)

    async def _unset_local_identity(self, repo_root: Path) -> None:
        for key in ("user.name", "user.email"):
            try:
                await self._run(["config", "--local", "--unset", key], cwd=repo_root)
            except GitCommandError:
                continue

    async def _config_scoped(self, repo_root: Path, key: str, *, scope: str) -> str | None:
        flag = "--local" if scope == "local" else "--global"
        try:
            value = (await self._run_text(["config", flag, "--get", key], cwd=repo_root)).strip()
        except GitCommandError:
            return None
        return value or None

    async def _run(self, args: list[str], *, cwd: Path) -> None:
        await self._run_text(args, cwd=cwd)

    async def _run_text(self, args: list[str], *, cwd: Path) -> str:
        """Run git off the asyncio thread.

        On Windows packaged apps, ``CreateProcess`` for console tools can block
        the calling thread for a long time. Doing that on the event loop freezes
        every HTTP handler (interpreters, reports, health). Always use a worker
        thread + ``subprocess.run``.
        """
        if shutil.which("git") is None:
            raise GitCommandError(git_missing_message())

        timeout = self._timeout
        if args and args[0] in {
            "status",
            "rev-parse",
            "diff",
            "log",
            "branch",
            "config",
            "remote",
            "show",
        }:
            timeout = min(timeout, 15.0)

        try:
            return await run_blocking(
                self._run_text_sync,
                list(args),
                Path(cwd),
                timeout,
            )
        except subprocess.TimeoutExpired as exc:
            raise GitCommandError("Git command timed out") from exc

    @staticmethod
    def _run_text_sync(args: list[str], cwd: Path, timeout: float) -> str:
        command = ["git", *args]
        try:
            result = subprocess.run(
                command,
                cwd=str(cwd),
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
                **windows_no_window_kwargs(),
            )
        except FileNotFoundError as exc:
            raise GitCommandError(git_missing_message()) from exc
        except OSError as exc:
            raise GitCommandError(f"Failed to start git: {exc}") from exc

        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            raise GitCommandError(detail or f"git {' '.join(args)} failed")

        return result.stdout or ""


def _parse_porcelain(raw: str) -> list[GitFileChange]:
    changes: list[GitFileChange] = []
    for line in raw.splitlines():
        if len(line) < 4:
            continue
        code = line[:2]
        path_part = line[3:].strip()
        if " -> " in path_part:
            old_path, new_path = path_part.split(" -> ", 1)
            changes.append(
                GitFileChange(
                    path=new_path,
                    old_path=old_path,
                    status=GitFileStatus.RENAMED,
                ),
            )
            continue
        changes.append(_name_status_to_change(code.strip(), path_part))
    return changes


def _parse_remotes(raw: str) -> list[GitRemote]:
    """Parse `git remote -v` into unique name/url pairs (prefer fetch URL)."""
    by_name: dict[str, GitRemote] = {}
    for line in raw.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        name, url = parts[0], parts[1]
        kind = parts[2].strip("()") if len(parts) >= 3 else "fetch"
        if name in by_name and kind != "fetch":
            continue
        by_name[name] = GitRemote(name=name, url=url)
    return list(by_name.values())


def _name_status_to_change(code: str, path: str) -> GitFileChange:
    return GitFileChange(path=path, status=_code_to_status(code))


def _code_to_status(code: str) -> GitFileStatus:
    normalized = code.strip().upper()
    if normalized.startswith("R"):
        return GitFileStatus.RENAMED
    if normalized.startswith("A") or normalized.endswith("A"):
        return GitFileStatus.ADDED
    if normalized.startswith("D") or normalized.endswith("D"):
        return GitFileStatus.DELETED
    if normalized.startswith("?"):
        return GitFileStatus.UNTRACKED
    if normalized.startswith("C"):
        return GitFileStatus.COPIED
    return GitFileStatus.MODIFIED


def _parse_unified_diff(raw: str, file_path: str | None) -> GitDiff:
    lines: list[GitDiffLine] = []
    left_line = 0
    right_line = 0
    old_path = file_path
    current_path = file_path

    for row in raw.splitlines():
        if row.startswith("--- "):
            old_path = row[4:].strip()
            if old_path.startswith("a/"):
                old_path = old_path[2:]
            continue
        if row.startswith("+++ "):
            current_path = row[4:].strip()
            if current_path.startswith("b/"):
                current_path = current_path[2:]
            continue
        if row.startswith("@@"):
            continue
        if not row:
            lines.append(GitDiffLine(kind="context", left="", right=""))
            continue
        marker = row[0]
        content = row[1:] if len(row) > 1 else ""
        if marker == "+":
            right_line += 1
            lines.append(
                GitDiffLine(
                    kind="added",
                    right=content,
                    right_line=right_line,
                ),
            )
        elif marker == "-":
            left_line += 1
            lines.append(
                GitDiffLine(
                    kind="removed",
                    left=content,
                    left_line=left_line,
                ),
            )
        elif marker == " ":
            left_line += 1
            right_line += 1
            lines.append(
                GitDiffLine(
                    kind="context",
                    left=content,
                    right=content,
                    left_line=left_line,
                    right_line=right_line,
                ),
            )
    return GitDiff(file_path=current_path or file_path, old_path=old_path, lines=lines)
