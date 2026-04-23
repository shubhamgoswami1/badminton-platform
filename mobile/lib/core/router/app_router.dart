import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/phone_entry_screen.dart';
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
  static const phoneEntry = '/phone';
  static const otp = '/otp';
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
      final loc = state.matchedLocation;

      // Let splash handle its own redirect.
      if (loc == AppRoutes.splash) return null;

      // Auth screens are always accessible when logged out.
      final isAuthScreen = loc == AppRoutes.welcome ||
          loc == AppRoutes.phoneEntry ||
          loc == AppRoutes.otp;

      if (!isLoggedIn && !isAuthScreen) return AppRoutes.welcome;
      if (isLoggedIn && isAuthScreen) return AppRoutes.home;
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
