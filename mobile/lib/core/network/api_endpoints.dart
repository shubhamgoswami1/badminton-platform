abstract final class ApiEndpoints {
  // Base URL is injected via --dart-define=API_BASE_URL at build time.
  // Falls back to local dev server.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  // Auth
  static const String otpRequest = '/auth/otp/request';
  static const String otpVerify = '/auth/otp/verify';
  static const String tokenRefresh = '/auth/token/refresh';
  static const String logout = '/auth/logout';

  // Users / Profile
  static const String me = '/users/me';
  static const String myProfile = '/users/me/profile';
  static String userProfile(String userId) => '/users/$userId/profile';

  // Tournaments
  static const String tournaments = '/tournaments';
  static String tournament(String id) => '/tournaments/$id';
  static String tournamentStatus(String id) => '/tournaments/$id/status';
  static String participants(String id) => '/tournaments/$id/participants';
  static String participant(String tid, String pid) => '/tournaments/$tid/participants/$pid';
  static String seedOrder(String id) => '/tournaments/$id/participants/seed-order';
  static String generateBracket(String id) => '/tournaments/$id/bracket/generate';
  static String bracket(String id) => '/tournaments/$id/bracket';
  static String matches(String id) => '/tournaments/$id/matches';
  static String standings(String id) => '/tournaments/$id/standings';

  // Scores
  static String matchScore(String matchId) => '/matches/$matchId/score';
  static String matchWalkover(String matchId) => '/matches/$matchId/walkover';

  // Training
  static const String trainingLogs = '/training/logs';
  static String trainingLog(String id) => '/training/logs/$id';
  static const String trainingGoals = '/training/goals';
  static String trainingGoal(String id) => '/training/goals/$id';

  // Discovery
  static const String discoverPlayers = '/discovery/players';
  static const String discoverTournaments = '/discovery/tournaments';
  static const String venues = '/discovery/venues';
}
