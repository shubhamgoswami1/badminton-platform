"""add latitude and longitude to tournaments

Adds optional GPS coordinates to the tournaments table, enabling the
GET /tournaments/nearby bounding-box + haversine discovery endpoint.

Revision ID: 0014
Revises: 0013
Create Date: 2026-04-24
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: Union[str, None] = "0013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # GPS coordinates for the tournament venue — optional.
    op.add_column(
        "tournaments",
        sa.Column("latitude", sa.Double(), nullable=True),
    )
    op.add_column(
        "tournaments",
        sa.Column("longitude", sa.Double(), nullable=True),
    )

    # Composite index for bounding-box queries.
    op.create_index(
        "ix_tournaments_lat_lng",
        "tournaments",
        ["latitude", "longitude"],
        postgresql_where=sa.text("latitude IS NOT NULL AND longitude IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_tournaments_lat_lng", table_name="tournaments")
    op.drop_column("tournaments", "longitude")
    op.drop_column("tournaments", "latitude")
