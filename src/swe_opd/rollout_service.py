from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import error, parse, request


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def tail_text(path: Path, max_lines: int = 40) -> str:
    if not path.exists():
        return ""
    with path.open("r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    return "".join(lines[-max_lines:])


def parse_json_request(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = int(handler.headers.get("Content-Length", "0"))
    body = handler.rfile.read(content_length) if content_length else b"{}"
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise TypeError("Expected top-level JSON object")
    return payload


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: Any) -> None:
    encoded = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(encoded)))
    handler.end_headers()
    handler.wfile.write(encoded)


def get_bearer_token(headers: Any) -> str:
    auth = headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[len("Bearer ") :]
    return ""


def normalize_service_base(api_base: str) -> str:
    return api_base.rstrip("/")


@dataclass
class RolloutJob:
    job_id: str
    request: dict[str, Any]
    job_dir: Path
    status: str = "queued"
    created_at: str = field(default_factory=utc_now)
    started_at: str = ""
    finished_at: str = ""
    returncode: int | None = None
    error: str = ""
    command: list[str] = field(default_factory=list)

    @property
    def stdout_path(self) -> Path:
        return self.job_dir / "stdout.log"

    @property
    def stderr_path(self) -> Path:
        return self.job_dir / "stderr.log"

    @property
    def result_path(self) -> Path:
        return self.job_dir / "result.json"

    @property
    def metadata_path(self) -> Path:
        return self.job_dir / "job.json"


class RolloutJobManager:
    def __init__(self, *, project_root: Path, job_root: Path, max_workers: int):
        self.project_root = project_root
        self.job_root = job_root
        self.job_root.mkdir(parents=True, exist_ok=True)
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.lock = threading.Lock()
        self.jobs: dict[str, RolloutJob] = {}

    def submit(self, job_request: dict[str, Any]) -> RolloutJob:
        job_id = uuid.uuid4().hex[:12]
        job_dir = self.job_root / job_id
        job_dir.mkdir(parents=True, exist_ok=True)
        job = RolloutJob(job_id=job_id, request=job_request, job_dir=job_dir)
        write_json(job_dir / "request.json", job_request)
        self._persist_job(job)
        with self.lock:
            self.jobs[job_id] = job
        self.executor.submit(self._run_job, job)
        return job

    def get(self, job_id: str) -> RolloutJob | None:
        with self.lock:
            return self.jobs.get(job_id)

    def list_jobs(self) -> list[RolloutJob]:
        with self.lock:
            return sorted(self.jobs.values(), key=lambda job: job.created_at, reverse=True)

    def _persist_job(self, job: RolloutJob) -> None:
        write_json(
            job.metadata_path,
            {
                "job_id": job.job_id,
                "status": job.status,
                "created_at": job.created_at,
                "started_at": job.started_at,
                "finished_at": job.finished_at,
                "returncode": job.returncode,
                "error": job.error,
                "command": job.command,
                "request": job.request,
                "job_dir": str(job.job_dir),
                "stdout_path": str(job.stdout_path),
                "stderr_path": str(job.stderr_path),
                "result_path": str(job.result_path),
            },
        )

    def _run_job(self, job: RolloutJob) -> None:
        job.status = "running"
        job.started_at = utc_now()
        self._persist_job(job)

        try:
            cmd, env = build_rollout_command(
                request_payload=job.request,
                project_root=self.project_root,
                job_dir=job.job_dir,
            )
            job.command = cmd
            self._persist_job(job)

            with job.stdout_path.open("w", encoding="utf-8") as stdout_f, job.stderr_path.open(
                "w", encoding="utf-8"
            ) as stderr_f:
                completed = subprocess.run(
                    cmd,
                    cwd=self.project_root,
                    env=env,
                    text=True,
                    stdout=stdout_f,
                    stderr=stderr_f,
                )

            job.returncode = completed.returncode
            if completed.returncode == 0:
                job.status = "succeeded"
            else:
                job.status = "failed"
                job.error = f"Rollout command exited with rc={completed.returncode}"

            result_payload = collect_job_result(job)
            write_json(job.result_path, result_payload)
        except Exception as exc:  # pragma: no cover - best effort service guard
            job.status = "failed"
            job.returncode = -1
            job.error = f"{type(exc).__name__}: {exc}"
            write_json(
                job.result_path,
                {
                    "job_id": job.job_id,
                    "status": job.status,
                    "error": job.error,
                    "job_dir": str(job.job_dir),
                },
            )
        finally:
            job.finished_at = utc_now()
            self._persist_job(job)


def _stringify_env_overrides(overrides: dict[str, Any]) -> dict[str, str]:
    env: dict[str, str] = {}
    for key, value in overrides.items():
        if value is None:
            continue
        env[key] = str(value)
    return env


def build_rollout_command(*, request_payload: dict[str, Any], project_root: Path, job_dir: Path) -> tuple[list[str], dict[str, str]]:
    job_kind = str(request_payload.get("kind", "single")).strip().lower()
    env = os.environ.copy()

    env["REMOTE_CONFIG_OUTPUT_PATH"] = str(job_dir / "generated" / "mini_sweagent.remote_sglang.yaml")

    env_mapping = {
        "subset": "SWEBENCH_SUBSET",
        "split": "SWEBENCH_SPLIT",
        "workers": "SWEBENCH_WORKERS",
        "docker_start_concurrency": "SWEBENCH_DOCKER_START_CONCURRENCY",
        "base_config": "MINI_BASE_CONFIG",
        "remote_api_base": "REMOTE_API_BASE",
        "remote_api_key": "REMOTE_API_KEY",
        "remote_model_name": "REMOTE_MODEL_NAME",
        "remote_provider": "REMOTE_PROVIDER",
        "remote_temperature": "REMOTE_TEMPERATURE",
        "remote_drop_params": "REMOTE_DROP_PARAMS",
    }
    for payload_key, env_key in env_mapping.items():
        if payload_key in request_payload and request_payload[payload_key] is not None:
            env[env_key] = str(request_payload[payload_key])

    env.update(_stringify_env_overrides(request_payload.get("env_overrides", {})))

    if job_kind == "single":
        instance_spec = request_payload.get("instance_id") or request_payload.get("instance")
        if not instance_spec:
            raise ValueError("single rollout requires `instance_id` or `instance`")
        env["SWEBENCH_OUTPUT_ROOT"] = str(job_dir / "artifacts")
        cmd = [
            "bash",
            str(project_root / "scripts/agent_rollout/run_swebench_single.sh"),
            str(instance_spec),
        ]
        cmd.extend([str(arg) for arg in request_payload.get("extra_args", [])])
        return cmd, env

    if job_kind == "batch":
        env["SWEBENCH_OUTPUT_DIR"] = str(job_dir / "artifacts")
        cmd = [
            "bash",
            str(project_root / "scripts/agent_rollout/run_swebench_batch.sh"),
        ]

        if request_payload.get("slice"):
            cmd.extend(["--slice", str(request_payload["slice"])])
        if request_payload.get("filter"):
            cmd.extend(["--filter", str(request_payload["filter"])])
        if request_payload.get("workers") is not None:
            cmd.extend(["--workers", str(request_payload["workers"])])
        if request_payload.get("docker_start_concurrency") is not None:
            cmd.extend(["--docker-start-concurrency", str(request_payload["docker_start_concurrency"])])
        cmd.extend([str(arg) for arg in request_payload.get("extra_args", [])])
        return cmd, env

    raise ValueError(f"Unsupported rollout kind: {job_kind}")


def collect_job_result(job: RolloutJob) -> dict[str, Any]:
    artifacts_root = job.job_dir / "artifacts"
    trajectory_files = sorted(artifacts_root.rglob("*.traj.json"))
    preds_files = sorted(artifacts_root.rglob("preds.json"))
    trajectory_summaries = []

    for path in trajectory_files:
        try:
            payload = load_json(path)
        except Exception:
            continue
        info = payload.get("info", {})
        trajectory_summaries.append(
            {
                "path": str(path),
                "instance_id": payload.get("instance_id"),
                "exit_status": info.get("exit_status"),
            }
        )

    return {
        "job_id": job.job_id,
        "kind": job.request.get("kind", "single"),
        "status": job.status,
        "returncode": job.returncode,
        "error": job.error,
        "request": job.request,
        "job_dir": str(job.job_dir),
        "rendered_config_path": str(job.job_dir / "generated" / "mini_sweagent.remote_sglang.yaml"),
        "stdout_path": str(job.stdout_path),
        "stderr_path": str(job.stderr_path),
        "artifacts_root": str(artifacts_root),
        "trajectory_files": [str(path) for path in trajectory_files],
        "preds_files": [str(path) for path in preds_files],
        "trajectory_summaries": trajectory_summaries,
    }


def summarize_job(job: RolloutJob) -> dict[str, Any]:
    payload = {
        "job_id": job.job_id,
        "status": job.status,
        "created_at": job.created_at,
        "started_at": job.started_at,
        "finished_at": job.finished_at,
        "returncode": job.returncode,
        "error": job.error,
        "kind": job.request.get("kind", "single"),
        "request": job.request,
        "job_dir": str(job.job_dir),
        "stdout_tail": tail_text(job.stdout_path),
        "stderr_tail": tail_text(job.stderr_path),
        "result_available": job.result_path.exists(),
    }
    if job.command:
        payload["command"] = job.command
    return payload


class RolloutServiceHandler(BaseHTTPRequestHandler):
    server_version = "swe-opd-rollout-service/0.1"

    @property
    def job_manager(self) -> RolloutJobManager:
        return self.server.job_manager  # type: ignore[attr-defined]

    @property
    def api_token(self) -> str:
        return self.server.api_token  # type: ignore[attr-defined]

    def do_GET(self) -> None:  # noqa: N802
        if not self._check_auth():
            return

        parsed = parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if path == "/healthz":
            json_response(
                self,
                HTTPStatus.OK,
                {
                    "ok": True,
                    "service": "rollout",
                    "jobs": len(self.job_manager.list_jobs()),
                },
            )
            return

        if path == "/v1/jobs":
            jobs = [summarize_job(job) for job in self.job_manager.list_jobs()]
            json_response(self, HTTPStatus.OK, {"jobs": jobs})
            return

        if path.startswith("/v1/jobs/"):
            suffix = path[len("/v1/jobs/") :]
            if suffix.endswith("/result"):
                job_id = suffix[: -len("/result")].strip("/")
                return self._handle_job_result(job_id)
            return self._handle_job_status(suffix)

        json_response(self, HTTPStatus.NOT_FOUND, {"error": f"Unknown path: {path}"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._check_auth():
            return

        parsed = parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if path != "/v1/jobs":
            json_response(self, HTTPStatus.NOT_FOUND, {"error": f"Unknown path: {path}"})
            return

        try:
            payload = parse_json_request(self)
            job = self.job_manager.submit(payload)
            json_response(self, HTTPStatus.ACCEPTED, summarize_job(job))
        except Exception as exc:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"error": f"{type(exc).__name__}: {exc}"},
            )

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), fmt % args))

    def _check_auth(self) -> bool:
        if not self.api_token:
            return True
        if get_bearer_token(self.headers) == self.api_token:
            return True
        json_response(self, HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid bearer token"})
        return False

    def _handle_job_status(self, job_id: str) -> None:
        job = self.job_manager.get(job_id)
        if job is None:
            json_response(self, HTTPStatus.NOT_FOUND, {"error": f"Unknown job id: {job_id}"})
            return
        json_response(self, HTTPStatus.OK, summarize_job(job))

    def _handle_job_result(self, job_id: str) -> None:
        job = self.job_manager.get(job_id)
        if job is None:
            json_response(self, HTTPStatus.NOT_FOUND, {"error": f"Unknown job id: {job_id}"})
            return
        if not job.result_path.exists():
            json_response(self, HTTPStatus.CONFLICT, {"error": "Result not ready yet", "status": job.status})
            return
        json_response(self, HTTPStatus.OK, load_json(job.result_path))


def run_service(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).resolve()
    job_root = Path(args.job_root).resolve()
    manager = RolloutJobManager(project_root=project_root, job_root=job_root, max_workers=args.max_workers)
    server = ThreadingHTTPServer((args.host, args.port), RolloutServiceHandler)
    server.job_manager = manager  # type: ignore[attr-defined]
    server.api_token = args.api_token or ""  # type: ignore[attr-defined]

    print(f"Starting rollout service on http://{args.host}:{args.port}", file=sys.stderr)
    print(f"Project root: {project_root}", file=sys.stderr)
    print(f"Job root: {job_root}", file=sys.stderr)
    print(f"Max workers: {args.max_workers}", file=sys.stderr)
    server.serve_forever()
    return 0


def service_http_request(
    *,
    method: str,
    api_base: str,
    path: str,
    api_token: str = "",
    payload: dict[str, Any] | None = None,
) -> Any:
    url = f"{normalize_service_base(api_base)}{path}"
    headers = {"Content-Type": "application/json"}
    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = request.Request(url, data=data, method=method, headers=headers)
    with request.urlopen(req, timeout=60) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        return json.loads(body) if body else None


def client_submit(args: argparse.Namespace) -> int:
    payload: dict[str, Any] = {"kind": args.kind}
    if args.kind == "single":
        payload["instance_id"] = args.instance_id
    else:
        if args.slice:
            payload["slice"] = args.slice
        if args.filter:
            payload["filter"] = args.filter
        if args.workers is not None:
            payload["workers"] = args.workers
        if args.docker_start_concurrency is not None:
            payload["docker_start_concurrency"] = args.docker_start_concurrency

    if args.subset:
        payload["subset"] = args.subset
    if args.split:
        payload["split"] = args.split
    if args.base_config:
        payload["base_config"] = args.base_config
    if args.remote_api_base:
        payload["remote_api_base"] = args.remote_api_base
    if args.remote_model_name:
        payload["remote_model_name"] = args.remote_model_name
    if args.env_override:
        payload["env_overrides"] = dict(item.split("=", 1) for item in args.env_override)
    if args.extra_arg:
        payload["extra_args"] = args.extra_arg

    response = service_http_request(
        method="POST",
        api_base=args.service_base,
        path="/v1/jobs",
        api_token=args.api_token,
        payload=payload,
    )
    print(json.dumps(response, indent=2, ensure_ascii=False))
    return 0


def client_status(args: argparse.Namespace) -> int:
    response = service_http_request(
        method="GET",
        api_base=args.service_base,
        path=f"/v1/jobs/{args.job_id}",
        api_token=args.api_token,
    )
    print(json.dumps(response, indent=2, ensure_ascii=False))
    return 0


def client_result(args: argparse.Namespace) -> int:
    response = service_http_request(
        method="GET",
        api_base=args.service_base,
        path=f"/v1/jobs/{args.job_id}/result",
        api_token=args.api_token,
    )
    print(json.dumps(response, indent=2, ensure_ascii=False))
    return 0


def client_wait(args: argparse.Namespace) -> int:
    deadline = time.time() + args.timeout if args.timeout else None
    while True:
        status_payload = service_http_request(
            method="GET",
            api_base=args.service_base,
            path=f"/v1/jobs/{args.job_id}",
            api_token=args.api_token,
        )
        status = status_payload.get("status")
        if status in {"succeeded", "failed"}:
            print(json.dumps(status_payload, indent=2, ensure_ascii=False))
            return 0 if status == "succeeded" else 1
        if deadline is not None and time.time() >= deadline:
            print(json.dumps(status_payload, indent=2, ensure_ascii=False))
            print("Timed out while waiting for rollout job", file=sys.stderr)
            return 2
        time.sleep(args.poll_interval)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="HTTP rollout service for remote SWE-bench execution.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve = subparsers.add_parser("serve", help="Start the rollout service.")
    serve.add_argument("--host", default="0.0.0.0")
    serve.add_argument("--port", type=int, default=18080)
    serve.add_argument("--project-root", required=True)
    serve.add_argument("--job-root", required=True)
    serve.add_argument("--max-workers", type=int, default=2)
    serve.add_argument("--api-token", default="")
    serve.set_defaults(func=run_service)

    submit = subparsers.add_parser("submit", help="Submit a rollout job to the remote service.")
    submit.add_argument("--service-base", required=True)
    submit.add_argument("--api-token", default="")
    submit.add_argument("--kind", choices=["single", "batch"], required=True)
    submit.add_argument("--instance-id", default="")
    submit.add_argument("--slice", default="")
    submit.add_argument("--filter", default="")
    submit.add_argument("--workers", type=int)
    submit.add_argument("--docker-start-concurrency", type=int)
    submit.add_argument("--subset", default="")
    submit.add_argument("--split", default="")
    submit.add_argument("--base-config", default="")
    submit.add_argument("--remote-api-base", default="")
    submit.add_argument("--remote-model-name", default="")
    submit.add_argument("--env-override", action="append", default=[])
    submit.add_argument("--extra-arg", action="append", default=[])
    submit.set_defaults(func=client_submit)

    status = subparsers.add_parser("status", help="Get rollout job status.")
    status.add_argument("--service-base", required=True)
    status.add_argument("--api-token", default="")
    status.add_argument("--job-id", required=True)
    status.set_defaults(func=client_status)

    result = subparsers.add_parser("result", help="Get rollout job result.")
    result.add_argument("--service-base", required=True)
    result.add_argument("--api-token", default="")
    result.add_argument("--job-id", required=True)
    result.set_defaults(func=client_result)

    wait = subparsers.add_parser("wait", help="Wait for rollout job completion.")
    wait.add_argument("--service-base", required=True)
    wait.add_argument("--api-token", default="")
    wait.add_argument("--job-id", required=True)
    wait.add_argument("--poll-interval", type=float, default=5.0)
    wait.add_argument("--timeout", type=float, default=0.0)
    wait.set_defaults(func=client_wait)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
