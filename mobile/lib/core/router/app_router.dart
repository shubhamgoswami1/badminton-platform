import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/matches/screens/matches_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/tournaments/screens/tournaments_screen.dart';
import '../../features/training/screens/training_screen.dart';
import '../storage/token_storage.dart';
import 'shell_scaffold.dart';

// Route paths
abstract final class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const home = '/home';
  static const tournaments = '/tournaments';
  static const matches = '/matches';
  static const training = '/training';
  static const profile = '/profile';
}

final routerProvider = Provider<GoRouter>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) async {
      final isLoggedIn = await tokenStorage.isLoggedIn();
      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isWelcome = state.matchedLocation == AppRoutes.welcome;

      // Let splash handle its own redirect after init
      if (isSplash) return null;

      if (!isLoggedIn && !isWelcome) return AppRoutes.welcome;
      if (isLoggedIn && isWelcome) return AppRoutes.home;
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
