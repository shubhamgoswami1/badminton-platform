"""add player search indexes

Revision ID: 0018
Revises: 0017
Create Date: 2026-05-14

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0018"
down_revision: Union[str, None] = "0017"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Functional index on lower(display_name) — supports prefix-search queries:
    #   WHERE lower(display_name) LIKE 'query%'
    op.create_index(
        "ix_player_profiles_display_name_lower",
        "player_profiles",
        [op.f("lower(display_name)")],
        postgresql_ops={"lower(display_name)": "text_pattern_ops"},
    )

    # B-tree index on elo_rating — supports range queries (elo_min / elo_max)
    # and ORDER BY elo_rating DESC NULLS LAST.
    op.create_index(
        "ix_player_profiles_elo_rating",
        "player_profiles",
        ["elo_rating"],
        postgresql_where="elo_rating IS NOT NULL",
    )

    # Composite index on (latitude, longitude) — supports bounding-box pre-filter
    # before the exact haversine radius check.
    op.create_index(
        "ix_player_profiles_lat_lng",
        "player_profiles",
        ["latitude", "longitude"],
        postgresql_where="latitude IS NOT NULL AND longitude IS NOT NULL",
    )


def downgrade() -> None:
    op.drop_index("ix_player_profiles_lat_lng", table_name="player_profiles")
    op.drop_index("ix_player_profiles_elo_rating", table_name="player_profiles")
    op.drop_index("ix_player_profiles_display_name_lower", table_name="player_profiles")
