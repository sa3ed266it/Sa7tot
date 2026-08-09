from __future__ import annotations


class DomainError(Exception):
    def __init__(self, status_code: int, detail: str, code: str = "invalid_request") -> None:
        self.status_code = status_code
        self.detail = detail
        self.code = code
        super().__init__(detail)
