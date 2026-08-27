from abc import ABC, abstractmethod


class LanguageService(ABC):
    @abstractmethod
    async def completion(self, request: dict) -> list[dict]: ...

    @abstractmethod
    async def hover(self, request: dict) -> dict | None: ...

    @abstractmethod
    async def diagnostics(self, request: dict) -> list[dict]: ...

    @abstractmethod
    async def definition(self, request: dict) -> dict | None: ...

    @abstractmethod
    async def references(self, request: dict) -> list[dict]: ...

    @abstractmethod
    async def rename(self, request: dict) -> dict: ...

    @abstractmethod
    async def format_document(self, request: dict) -> str: ...

    @abstractmethod
    async def signature_help(self, request: dict) -> dict | None: ...
