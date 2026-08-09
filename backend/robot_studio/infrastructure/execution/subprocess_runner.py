"""Subprocess-based Robot Framework runner."""

from __future__ import annotations

import asyncio
import os
import signal
import sys
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

from robot_studio.domain.interfaces.runner import Runner
from robot_studio.domain.models import ExecutionStatus


class RunnerError(Exception):
    """Raised when the runner cannot start or manage a process."""


@dataclass
class _RunProcess:
    run_id: UUID
    process: asyncio.subprocess.Process
    status: ExecutionStatus
    started_at: datetime
    output_dir: Path
    command: list[str]
    queue: asyncio.Queue[str | None] = field(default_factory=asyncio.Queue)
    reader_task: asyncio.Task | None = None
    wait_task: asyncio.Task | None = None
    exit_code: int | None = None
    finished: asyncio.Event = field(default_factory=asyncio.Event)


class SubprocessRunner(Runner):
    """Runs `python -m robot` inside an active virtual environment."""

    def __init__(self, *, default_timeout: float | None = None) -> None:
        self._runs: dict[UUID, _RunProcess] = {}
        self._default_timeout = default_timeout
        self._lock = asyncio.Lock()

    async def start(self, request: dict) -> dict:
        python = Path(str(request["python_executable"])).expanduser().resolve()
        if not python.is_file():
            raise RunnerError(f"Python executable not found: '{python}'")

        suite = str(request["suite"])
        output_dir = Path(str(request["output_dir"]))
        output_dir.mkdir(parents=True, exist_ok=True)

        cwd = Path(str(request.get("cwd") or ".")).resolve()
        timeout = request.get("timeout", self._default_timeout)
        run_id = UUID(str(request["run_id"])) if request.get("run_id") else uuid4()

        extra_args = [
            str(arg)
            for arg in (request.get("robot_args") or [])
            if str(arg).strip()
        ]

        listener = Path(__file__).with_name("studio_progress_listener.py")
        # Prepend so project --listener args still run; ours stays first for UI.
        if listener.is_file():
            extra_args = ["--listener", str(listener.resolve()), *extra_args]

        command = [
            str(python),
            "-u",  # unbuffered stdout so Live Output streams during the run
            "-m",
            "robot",
            "--outputdir",
            str(output_dir),
            "--output",
            "output.xml",
            "--log",
            "log.html",
            "--report",
            "report.html",
            *extra_args,
            suite,
        ]

        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"

        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                cwd=str(cwd),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                start_new_session=sys.platform != "win32",
                env=env,
            )
        except OSError as exc:
            raise RunnerError(f"Failed to start robot: {exc}") from exc

        run = _RunProcess(
            run_id=run_id,
            process=process,
            status=ExecutionStatus.RUNNING,
            started_at=datetime.now(UTC),
            output_dir=output_dir,
            command=command,
        )
        run.reader_task = asyncio.create_task(self._read_output(run))
        run.wait_task = asyncio.create_task(self._wait_for_exit(run, timeout))
        async with self._lock:
            self._runs[run_id] = run

        return {
            "run_id": str(run_id),
            "status": ExecutionStatus.RUNNING.value,
            "output_dir": str(output_dir),
            "command": " ".join(command),
            "pid": process.pid,
        }

    async def stop(self, run_id: UUID) -> None:
        async with self._lock:
            run = self._runs.get(run_id)
        if run is None:
            raise RunnerError(f"No active run '{run_id}'")
        if run.status in {
            ExecutionStatus.FINISHED,
            ExecutionStatus.FAILED,
            ExecutionStatus.CANCELLED,
        }:
            return

        run.status = ExecutionStatus.STOPPING
        await self._terminate_tree(run.process)
        try:
            await asyncio.wait_for(run.process.wait(), timeout=5)
        except TimeoutError:
            await self._kill_tree(run.process)
            await run.process.wait()

        run.exit_code = run.process.returncode
        run.status = ExecutionStatus.CANCELLED
        run.finished.set()
        await run.queue.put(None)

    async def stream_output(self, run_id: UUID):
        async with self._lock:
            run = self._runs.get(run_id)
        if run is None:
            raise RunnerError(f"No active run '{run_id}'")

        while True:
            item = await run.queue.get()
            if item is None:
                break
            yield item

    def get_status(self, run_id: UUID) -> ExecutionStatus | None:
        run = self._runs.get(run_id)
        return run.status if run else None

    def get_exit_code(self, run_id: UUID) -> int | None:
        run = self._runs.get(run_id)
        return run.exit_code if run else None

    async def wait(self, run_id: UUID) -> int | None:
        async with self._lock:
            run = self._runs.get(run_id)
        if run is None:
            raise RunnerError(f"No active run '{run_id}'")
        await run.finished.wait()
        return run.exit_code

    def release(self, run_id: UUID) -> None:
        """Drop finished run state after the monitor has read the final status."""
        self._runs.pop(run_id, None)

    async def _read_output(self, run: _RunProcess) -> None:
        assert run.process.stdout is not None
        try:
            while True:
                line = await run.process.stdout.readline()
                if not line:
                    break
                text = line.decode("utf-8", errors="replace").rstrip("\n")
                await run.queue.put(text)
        finally:
            # Signal end-of-stream once process has exited (wait task may still finish).
            if run.finished.is_set():
                await run.queue.put(None)

    async def _wait_for_exit(
        self,
        run: _RunProcess,
        timeout: float | None,
    ) -> None:
        try:
            if timeout:
                code = await asyncio.wait_for(run.process.wait(), timeout=timeout)
            else:
                code = await run.process.wait()
        except TimeoutError:
            await self._terminate_tree(run.process)
            try:
                await asyncio.wait_for(run.process.wait(), timeout=5)
            except TimeoutError:
                await self._kill_tree(run.process)
                await run.process.wait()
            run.exit_code = run.process.returncode
            if run.status != ExecutionStatus.CANCELLED:
                run.status = ExecutionStatus.FAILED
        else:
            run.exit_code = code
            if run.status == ExecutionStatus.STOPPING:
                run.status = ExecutionStatus.CANCELLED
            elif run.status != ExecutionStatus.CANCELLED:
                run.status = (
                    ExecutionStatus.FINISHED if code == 0 else ExecutionStatus.FAILED
                )
        finally:
            run.finished.set()
            await run.queue.put(None)

    async def _terminate_tree(self, process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        pid = process.pid
        if pid is None:
            return
        if sys.platform == "win32":
            await asyncio.create_subprocess_exec(
                "taskkill",
                "/PID",
                str(pid),
                "/T",
                "/F",
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            return
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except ProcessLookupError:
            process.terminate()

    async def _kill_tree(self, process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        pid = process.pid
        if pid is None:
            return
        if sys.platform == "win32":
            await self._terminate_tree(process)
            return
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except ProcessLookupError:
            process.kill()
