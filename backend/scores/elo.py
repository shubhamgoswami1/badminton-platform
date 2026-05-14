"""
Elo rating calculations for singles matches.

K  = 32     (standard for developing player pools)
DEFAULT_ELO = 1500.0  (starting rating for unrated players)

Expected score: E_a = 1 / (1 + 10^((R_b - R_a) / 400))
New rating:     R_a' = R_a + K * (S_a - E_a)
"""

K: float = 32.0
DEFAULT_ELO: float = 1500.0


def expected_score(rating_a: float, rating_b: float) -> float:
    """Return the expected score (probability of winning) for player A."""
    return 1.0 / (1.0 + 10.0 ** ((rating_b - rating_a) / 400.0))


def _new_rating(rating: float, score: float, expected: float) -> float:
    """Compute the new Elo rating after a result."""
    return rating + K * (score - expected)


def compute_elo_delta(
    rating_a: float | None,
    rating_b: float | None,
    a_won: bool,
) -> tuple[float, float]:
    """
    Compute new Elo ratings for both players given the match outcome.

    Args:
        rating_a: Current Elo for side A (None → DEFAULT_ELO).
        rating_b: Current Elo for side B (None → DEFAULT_ELO).
        a_won:    True if side A won; False if side B won.

    Returns:
        Tuple (new_rating_a, new_rating_b) rounded to 2 decimal places.
    """
    ra = rating_a if rating_a is not None else DEFAULT_ELO
    rb = rating_b if rating_b is not None else DEFAULT_ELO

    e_a = expected_score(ra, rb)
    e_b = 1.0 - e_a

    s_a = 1.0 if a_won else 0.0
    s_b = 0.0 if a_won else 1.0

    return round(_new_rating(ra, s_a, e_a), 2), round(_new_rating(rb, s_b, e_b), 2)
