"""create tournaments table

Revision ID: 0005
Revises: 0004
Create Date: 2026-04-17

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "tournaments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("organiser_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("title", sa.Text, nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("city", sa.Text, nullable=True),
        sa.Column("format", sa.Text, nullable=False),
        sa.Column("match_format", sa.Text, nullable=False),
        sa.Column("play_type", sa.Text, nullable=False),
        sa.Column("status", sa.Text, nullable=False, server_default="DRAFT"),
        sa.Column("max_participants", sa.Integer, nullable=True),
        sa.Column("registration_deadline", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("starts_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("bracket_generated", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("deleted_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.create_index("ix_tournaments_organiser_id", "tournaments", ["organiser_id"])
    op.create_index("ix_tournaments_status", "tournaments", ["status"])
    op.create_index("ix_tournaments_city", "tournaments", ["city"])


def downgrade() -> None:
    op.drop_table("tournaments")
