import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'scaffold_with_nav.dart';
import '../presentation/screens/dashboard/dashboard_screen.dart';
import '../presentation/screens/suggestions/suggestions_screen.dart';
import '../presentation/screens/suggestions/suggestion_detail_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/onboarding/onboarding_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorHome = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
final _shellNavigatorReview = GlobalKey<NavigatorState>(debugLabel: 'shellReview');
final _shellNavigatorSettings = GlobalKey<NavigatorState>(debugLabel: 'shellSettings');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNestedNavigation(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Home / Consolidated Overview
          StatefulShellBranch(
            navigatorKey: _shellNavigatorHome,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),

          // Branch 1: Review / Suggestions
          StatefulShellBranch(
            navigatorKey: _shellNavigatorReview,
            routes: [
              GoRoute(
                path: '/suggestions',
                builder: (context, state) => const SuggestionsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return SuggestionDetailScreen(suggestionId: id);
                    },
                  ),
                ],
              ),
            ],
          ),

          // Branch 3: Settings
          StatefulShellBranch(
            navigatorKey: _shellNavigatorSettings,
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Outside the persistent shell
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
  );
});
