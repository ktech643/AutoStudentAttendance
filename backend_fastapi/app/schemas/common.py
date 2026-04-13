from pydantic import BaseModel, Field


class MessageResponse(BaseModel):
    message: str


class PaginatedResponse(BaseModel):
    total: int = Field(ge=0)
