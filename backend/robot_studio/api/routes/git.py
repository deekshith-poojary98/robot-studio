from fastapi import APIRouter, Depends, HTTPException, Query

from robot_studio.api.gateway import RestGateway
from robot_studio.api.routes.health import get_gateway
from robot_studio.api.schemas.git import (
    GitAddRemoteRequest,
    GitBranchResponse,
    GitCheckoutRequest,
    GitCommitDetailResponse,
    GitCommitRequest,
    GitCommitResponse,
    GitCreateBranchRequest,
    GitDeleteBranchRequest,
    GitDiffResponse,
    GitIdentityRequest,
    GitIdentityResponse,
    GitRemoteResponse,
    GitRemoteResultResponse,
    GitRepositoryResponse,
    GitStatusResponse,
    to_branch_response,
    to_commit_detail_response,
    to_commit_response,
    to_diff_response,
    to_identity_response,
    to_remote_info_response,
    to_remote_response,
    to_repository_response,
    to_status_response,
)
from robot_studio.application.services.git_service import GitValidationError
from robot_studio.infrastructure.git.cli_provider import GitCommandError

router = APIRouter(prefix="/git", tags=["git"])


@router.get("/status", response_model=GitStatusResponse)
async def git_status(
    gateway: RestGateway = Depends(get_gateway),
) -> GitStatusResponse:
    try:
        status = await gateway.git_status()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if status is None:
        return GitStatusResponse(
            repository=GitRepositoryResponse(is_repository=False, clean=True),
        )
    return to_status_response(status)


@router.post("/init", response_model=GitRepositoryResponse)
async def git_init(
    gateway: RestGateway = Depends(get_gateway),
) -> GitRepositoryResponse:
    try:
        repository = await gateway.git_init()
    except (GitValidationError, GitCommandError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_repository_response(repository)


@router.get("/history", response_model=list[GitCommitResponse])
async def git_history(
    limit: int = Query(default=50, ge=1, le=200),
    gateway: RestGateway = Depends(get_gateway),
) -> list[GitCommitResponse]:
    try:
        commits = await gateway.git_history(limit=limit)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return [to_commit_response(item) for item in commits]


@router.get("/history/{commit_hash}", response_model=GitCommitDetailResponse)
async def git_commit_detail(
    commit_hash: str,
    gateway: RestGateway = Depends(get_gateway),
) -> GitCommitDetailResponse:
    try:
        detail = await gateway.git_commit_detail(commit_hash)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_commit_detail_response(detail)


@router.get("/branches", response_model=list[GitBranchResponse])
async def git_branches(
    gateway: RestGateway = Depends(get_gateway),
) -> list[GitBranchResponse]:
    try:
        branches = await gateway.git_branches()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return [to_branch_response(item) for item in branches]


@router.post("/checkout", response_model=GitRepositoryResponse)
async def git_checkout(
    request: GitCheckoutRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> GitRepositoryResponse:
    try:
        repository = await gateway.git_checkout(request.branch)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_repository_response(repository)


@router.post("/create-branch", response_model=GitBranchResponse)
async def git_create_branch(
    request: GitCreateBranchRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> GitBranchResponse:
    try:
        branch = await gateway.git_create_branch(
            request.name,
            start_point=request.start_point,
        )
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_branch_response(branch)


@router.post("/delete-branch")
async def git_delete_branch(
    request: GitDeleteBranchRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> dict[str, str]:
    try:
        await gateway.git_delete_branch(request.name)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"status": "deleted"}


@router.post("/commit", response_model=GitCommitResponse)
async def git_commit(
    request: GitCommitRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> GitCommitResponse:
    try:
        commit = await gateway.git_commit(request.message, files=request.files)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_commit_response(commit)


@router.post("/fetch", response_model=GitRemoteResultResponse)
async def git_fetch(
    gateway: RestGateway = Depends(get_gateway),
) -> GitRemoteResultResponse:
    try:
        result = await gateway.git_fetch()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_remote_response(result)


@router.post("/pull", response_model=GitRemoteResultResponse)
async def git_pull(
    gateway: RestGateway = Depends(get_gateway),
) -> GitRemoteResultResponse:
    try:
        result = await gateway.git_pull()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_remote_response(result)


@router.post("/push", response_model=GitRemoteResultResponse)
async def git_push(
    gateway: RestGateway = Depends(get_gateway),
) -> GitRemoteResultResponse:
    try:
        result = await gateway.git_push()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_remote_response(result)


@router.get("/remotes", response_model=list[GitRemoteResponse])
async def git_list_remotes(
    gateway: RestGateway = Depends(get_gateway),
) -> list[GitRemoteResponse]:
    try:
        remotes = await gateway.git_list_remotes()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return [to_remote_info_response(item) for item in remotes]


@router.get("/identity", response_model=GitIdentityResponse)
async def git_get_identity(
    gateway: RestGateway = Depends(get_gateway),
) -> GitIdentityResponse:
    try:
        identity = await gateway.git_get_identity()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_identity_response(identity)


@router.put("/identity", response_model=GitIdentityResponse)
async def git_set_identity(
    request: GitIdentityRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> GitIdentityResponse:
    try:
        identity = await gateway.git_set_identity(
            name=request.name,
            email=request.email,
            scope=request.scope,
        )
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_identity_response(identity)


@router.post("/remotes", response_model=list[GitRemoteResponse])
async def git_add_remote(
    request: GitAddRemoteRequest,
    gateway: RestGateway = Depends(get_gateway),
) -> list[GitRemoteResponse]:
    try:
        remotes = await gateway.git_add_remote(name=request.name, url=request.url)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return [to_remote_info_response(item) for item in remotes]


@router.post("/seed-local-remote")
async def git_seed_local_remote(
    gateway: RestGateway = Depends(get_gateway),
) -> dict[str, str]:
    """Create a bare remote under the workspace and wire origin + upstream."""
    try:
        remote_path = await gateway.git_seed_local_remote()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"remote_path": remote_path}


@router.get("/diff", response_model=GitDiffResponse)
async def git_diff(
    file: str | None = Query(default=None),
    commit: str | None = Query(default=None),
    gateway: RestGateway = Depends(get_gateway),
) -> GitDiffResponse:
    try:
        diff = await gateway.git_diff(file_path=file, commit=commit)
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return to_diff_response(diff)


@router.post("/refresh", response_model=GitRepositoryResponse | None)
async def git_refresh(
    gateway: RestGateway = Depends(get_gateway),
) -> GitRepositoryResponse | None:
    try:
        repository = await gateway.git_refresh()
    except GitValidationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if repository is None:
        return None
    return to_repository_response(repository)
