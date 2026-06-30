"""add idempotency records table

Revision ID: 0021
Revises: 0020
Create Date: 2026-05-18 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

# revision identifiers, used by Alembic.
revision = "0021"
down_revision = "0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "idempotency_records",
        sa.Column("key", sa.Text(), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("response_body", JSONB(), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("key"),
    )
    # Auto-expire after 24 hours — managed by a cron in production;
    # index on created_at makes the cleanup query fast.
    op.create_index(
        "ix_idempotency_records_created_at",
        "idempotency_records",
        ["created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_idempotency_records_created_at", table_name="idempotency_records")
    op.drop_table("idempotency_records")
