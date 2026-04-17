"""create venues table

Revision ID: 0011
Revises: 0010
Create Date: 2026-04-17

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0011"
down_revision: Union[str, None] = "0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venues",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("name", sa.Text, nullable=False),
        sa.Column("city", sa.Text, nullable=True),
        sa.Column("address", sa.Text, nullable=True),
        sa.Column("court_count", sa.Integer, nullable=True),
        sa.Column("submitted_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_venues_city", "venues", ["city"])

    # Also add indexes for discovery-related columns on existing tables
    op.create_index("ix_player_profiles_city", "player_profiles", ["city"])
    op.create_index("ix_player_profiles_skill_level", "player_profiles", ["skill_level"])


def downgrade() -> None:
    op.drop_index("ix_player_profiles_skill_level", "player_profiles")
    op.drop_index("ix_player_profiles_city", "player_profiles")
    op.drop_table("venues")
