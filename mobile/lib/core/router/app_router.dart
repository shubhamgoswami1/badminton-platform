import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/phone_entry_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/matches/screens/matches_screen.dart';
import '../../features/profile/screens/onboarding_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/tournaments/screens/create_tournament_screen.dart';
import '../../features/tournaments/screens/tournament_detail_screen.dart';
import '../../features/tournaments/screens/tournaments_screen.dart';
import '../../features/training/screens/training_screen.dart';
import 'shell_scaffold.dart';

// ── Route paths ────────────────────────────────────────────────────────────

abstract final class AppRoutes {
  static const splash           = '/';
  static const welcome          = '/welcome';
  static const phoneEntry       = '/phone';
  static const otp              = '/otp';
  static const onboarding       = '/onboarding';
  static const home             = '/home';
  static const tournaments      = '/tournaments';
  static const matches          = '/matches';
  static const training         = '/training';
  static const profile          = '/profile';

  // Tournament detail / create — full-screen (outside the shell).
  static const tournamentCreate = '/tournament/create';
  static const _tournamentDetail = '/tournament/:id';

  /// Navigation helper: build the path for a specific tournament.
  static String tournamentDetailPath(String id) => '/tournament/$id';
}

// ── Router provider ────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  // refreshListenable causes go_router to re-evaluate redirect() whenever
  // auth state changes (login, logout, onboarding completion, etc.).
  final listenable = ref.watch(authListenableProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc  = state.matchedLocation;

      // Splash manages its own navigation — never redirect away from it.
      if (loc == AppRoutes.splash) return null;

      final isAuthScreen = loc == AppRoutes.welcome ||
          loc == AppRoutes.phoneEntry ||
          loc == AppRoutes.otp;

      // Not logged in → auth screens only.
      if (!auth.isLoggedIn && !isAuthScreen) return AppRoutes.welcome;

      // Logged in + on an auth screen → go home (or onboarding if first login).
      if (auth.isLoggedIn && isAuthScreen) {
        return auth.isFirstLogin ? AppRoutes.onboarding : AppRoutes.home;
      }

      // Logged in + first login + not already on onboarding → force onboarding.
      if (auth.isLoggedIn &&
          auth.isFirstLogin &&
          loc != AppRoutes.onboarding) {
        return AppRoutes.onboarding;
      }

      // Logged in + onboarding done + still on onboarding page → push to home.
      if (auth.isLoggedIn &&
          !auth.isFirstLogin &&
          loc == AppRoutes.onboarding) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.phoneEntry,
        builder: (_, __) => const PhoneEntryScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) {
          final phone = state.extra as String? ?? '';
          return OtpScreen(phoneNumber: phone);
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),

      // ── Tournament full-screen routes (no bottom nav) ──────────────
      // Define create BEFORE :id so go_router prefers the static segment.
      GoRoute(
        path: AppRoutes.tournamentCreate,
        builder: (_, __) => const CreateTournamentScreen(),
      ),
      GoRoute(
        path: AppRoutes._tournamentDetail,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TournamentDetailScreen(tournamentId: id);
        },
      ),

      // ── Shell (bottom nav) ─────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.tournaments,
            builder: (_, __) => const TournamentsScreen(),
          ),
          GoRoute(
            path: AppRoutes.matches,
            builder: (_, __) => const MatchesScreen(),
          ),
          GoRoute(
            path: AppRoutes.training,
            builder: (_, __) => const TrainingScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});
