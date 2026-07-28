from pydantic import BaseModel, Field


class FileContentResponse(BaseModel):
    path: str
    content: str
    mtime: float
    size: int = 0


class FileWriteRequest(BaseModel):
    path: str
    content: str = ""


class FileWriteResponse(BaseModel):
    path: str
    mtime: float
    size: int = 0
    saved_at: str | None = None


class FileCreateRequest(BaseModel):
    path: str
    content: str = ""


class DirectoryCreateRequest(BaseModel):
    path: str


class FileRenameRequest(BaseModel):
    path: str
    new_name: str


class FileMoveRequest(BaseModel):
    path: str
    destination_dir: str


class FilePathRequest(BaseModel):
    path: str


class FileMutationResponse(BaseModel):
    path: str
    old_path: str | None = None
    is_dir: bool = False
    name: str | None = None
    deleted: bool = False
    mtime: float | None = None
    size: int | None = None
    saved_at: str | None = None


class FileTreeNode(BaseModel):
    name: str
    path: str
    relative_path: str
    is_dir: bool
    suffix: str = ""
    has_children: bool = False
    children: list["FileTreeNode"] = Field(default_factory=list)


class FileTreeResponse(BaseModel):
    entries: list[FileTreeNode] = Field(default_factory=list)
