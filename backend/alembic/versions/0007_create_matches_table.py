"""create matches and match_scores tables

Revision ID: 0007
Revises: 0006
Create Date: 2026-04-17

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "matches",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tournament_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tournaments.id", ondelete="CASCADE"), nullable=False),
        sa.Column("round", sa.Integer, nullable=False),
        sa.Column("match_number", sa.Integer, nullable=False),
        sa.Column("side_a_participant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tournament_participants.id", ondelete="SET NULL"), nullable=True),
        sa.Column("side_b_participant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tournament_participants.id", ondelete="SET NULL"), nullable=True),
        sa.Column("winner_participant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tournament_participants.id", ondelete="SET NULL"), nullable=True),
        sa.Column("status", sa.Text, nullable=False, server_default="PENDING"),
        sa.Column("scheduled_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("completed_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("next_match_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("winner_feeds_side", sa.Text, nullable=True),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_foreign_key("fk_matches_next_match_id", "matches", "matches", ["next_match_id"], ["id"], ondelete="SET NULL")
    op.create_index("ix_matches_tournament_id", "matches", ["tournament_id"])
    op.create_index("ix_matches_round", "matches", ["tournament_id", "round"])

    op.create_table(
        "match_scores",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("match_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("matches.id", ondelete="CASCADE"), nullable=False),
        sa.Column("set_number", sa.Integer, nullable=False),
        sa.Column("side_a_score", sa.Integer, nullable=False),
        sa.Column("side_b_score", sa.Integer, nullable=False),
        sa.Column("submitted_by", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("submitted_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_match_scores_match_id", "match_scores", ["match_id"])


def downgrade() -> None:
    op.drop_table("match_scores")
    op.drop_constraint("fk_matches_next_match_id", "matches", type_="foreignkey")
    op.drop_table("matches")
