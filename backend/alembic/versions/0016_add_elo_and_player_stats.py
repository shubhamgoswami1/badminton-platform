"""Add Elo rating and player stats to player_profiles; add elo_applied and version to matches.

Revision ID: 0016
Revises: 0015
Create Date: 2026-05-06
"""

from alembic import op
import sqlalchemy as sa

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # player_profiles: Elo system fields
    op.add_column(
        "player_profiles",
        sa.Column("elo_rating", sa.Float(), nullable=True),
    )
    op.add_column(
        "player_profiles",
        sa.Column(
            "matches_played",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "player_profiles",
        sa.Column(
            "wins",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )
    op.add_column(
        "player_profiles",
        sa.Column(
            "losses",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    # matches: prevent double Elo application + optimistic locking version
    op.add_column(
        "matches",
        sa.Column(
            "elo_applied",
            sa.Boolean(),
            nullable=False,
            server_default="false",
        ),
    )
    op.add_column(
        "matches",
        sa.Column(
            "version",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
    )


def downgrade() -> None:
    op.drop_column("player_profiles", "elo_rating")
    op.drop_column("player_profiles", "matches_played")
    op.drop_column("player_profiles", "wins")
    op.drop_column("player_profiles", "losses")
    op.drop_column("matches", "elo_applied")
    op.drop_column("matches", "version")
