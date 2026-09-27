import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../presentation/screens/dashboard/dashboard_screen.dart';
import '../presentation/screens/suggestions/suggestions_screen.dart';
import '../presentation/screens/suggestions/suggestion_detail_screen.dart';
import '../presentation/screens/portfolio/portfolio_screen.dart';
import '../presentation/screens/insights/insights_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/onboarding/onboarding_screen.dart';

part 'router.g.dart';

@riverpod
GoRouter router(RouterRef ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/suggestions',
        builder: (context, state) => const SuggestionsScreen(),
      ),
      GoRoute(
        path: '/suggestions/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SuggestionDetailScreen(suggestionId: id);
        },
      ),
      GoRoute(
        path: '/portfolio',
        builder: (context, state) => const PortfolioScreen(),
      ),
      GoRoute(
        path: '/insights',
        builder: (context, state) => const InsightsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
