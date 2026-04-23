"""add location, rating, reliability_score to player_profiles

Revision ID: 0013
Revises: 0012
Create Date: 2026-04-23

New columns:
  - latitude / longitude  : optional GPS coords stored for future radius search.
                             Filtering in MVP is city-string based; these are
                             populated when a client provides them so the data
                             is ready when GPS search is enabled post-MVP.
  - rating                : nullable float (0.0–10.0). Manually set or computed
                            from match results in a future phase. Enables range
                            queries today.
  - reliability_score     : float 0.0–5.0, NOT NULL, default 5.0. Represents
                            how reliably a player shows up to confirmed matches.
                            Starts at 5.0 (full trust) and degrades on no-shows.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0013"
down_revision: Union[str, None] = "0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "player_profiles",
        sa.Column("latitude", sa.Double(), nullable=True),
    )
    op.add_column(
        "player_profiles",
        sa.Column("longitude", sa.Double(), nullable=True),
    )
    op.add_column(
        "player_profiles",
        sa.Column(
            "reliability_score",
            sa.Float(),
            nullable=False,
            server_default="5.0",
        ),
    )
    op.add_column(
        "player_profiles",
        sa.Column("rating", sa.Float(), nullable=True),
    )
    # Index for text search on display_name (case-insensitive via lower())
    op.create_index(
        "ix_player_profiles_display_name_lower",
        "player_profiles",
        [sa.text("lower(display_name)")],
        postgresql_using="btree",
    )


def downgrade() -> None:
    op.drop_index("ix_player_profiles_display_name_lower", table_name="player_profiles")
    op.drop_column("player_profiles", "rating")
    op.drop_column("player_profiles", "reliability_score")
    op.drop_column("player_profiles", "longitude")
    op.drop_column("player_profiles", "latitude")
