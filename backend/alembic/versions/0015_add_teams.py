"""add teams table for doubles support

Creates a `teams` table that pairs two TournamentParticipants inside a
tournament.  participant_b_id is nullable so a team can be created before the
partner registers.  This is a scaffold — full doubles bracket support will be
wired up in a later phase.

Revision ID: 0015
Revises: 0014
Create Date: 2026-04-28
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision: str = "0015"
down_revision: Union[str, None] = "0014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "teams",
        sa.Column("id", UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column(
            "tournament_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tournaments.id"),
            nullable=False,
            index=True,
        ),
        sa.Column("name", sa.Text(), nullable=True),
        sa.Column(
            "participant_a_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tournament_participants.id"),
            nullable=False,
        ),
        sa.Column(
            "participant_b_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tournament_participants.id"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("ix_teams_tournament_id", "teams", ["tournament_id"])


def downgrade() -> None:
    op.drop_index("ix_teams_tournament_id", table_name="teams")
    op.drop_table("teams")
