import 'package:flutter/material.dart';

import '../core/game_localization.dart';
import '../core/world_state.dart';
import 'app_sidebar.dart';
import 'saves_controller.dart';
import 'saves_screen.dart';
import 'source_screen.dart';
import 'world_screen.dart';

/// Keeps the app chrome in place while routes animate in the content area.
class AppRouter extends StatefulWidget {
  const AppRouter({
    super.key,
    this.controller,
    this.pickDirectory,
    this.localizationRepository,
  });

  final SavesController? controller;
  final Future<String?> Function()? pickDirectory;
  final GameLocalizationRepository? localizationRepository;

  static const worldRoute = '/world';
  static const sourceRoute = '/source';

  static Future<void> openWorld(
    BuildContext context,
    WorldStateSnapshot snapshot,
  ) => Navigator.of(context).pushNamed<void>(worldRoute, arguments: snapshot);

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _language = ValueNotifier(GameLanguage.russian);
  late final SavesController controller;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? SavesController();
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar =
              constraints.maxWidth >= 1000 && constraints.maxHeight >= 650;
          return Row(
            children: [
              if (showSidebar)
                SizedBox(width: 240, child: AppSidebar(controller: controller)),
              Expanded(
                child: Navigator(key: _navigatorKey, onGenerateRoute: _route),
              ),
            ],
          );
        },
      ),
    ),
  );

  Route<void> _route(RouteSettings settings) {
    final Widget page;
    switch (settings.name) {
      case Navigator.defaultRouteName:
        page = SavesScreen(
          controller: controller,
          pickDirectory: widget.pickDirectory,
          language: _language,
          localizationRepository: widget.localizationRepository,
        );
      case AppRouter.worldRoute:
        final snapshot = settings.arguments;
        if (snapshot is! WorldStateSnapshot) {
          throw ArgumentError('Для страницы мира требуется снимок сохранения.');
        }
        page = WorldScreen(
          snapshot: snapshot,
          language: _language,
          localizationRepository: widget.localizationRepository,
          onChangeSource: () {
            _navigatorKey.currentState?.pushNamed<void>(AppRouter.sourceRoute);
          },
        );
      case AppRouter.sourceRoute:
        page = SourceScreen(
          language: _language,
          onSelectFiles: () {
            controller.clearSelection();
            _navigatorKey.currentState?.popUntil((route) => route.isFirst);
          },
        );
      default:
        throw ArgumentError('Неизвестный маршрут: ${settings.name}');
    }

    return PageRouteBuilder<void>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 360),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final entering =
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
            );
        final leaving =
            Tween<Offset>(begin: Offset.zero, end: const Offset(-1, 0)).animate(
              CurvedAnimation(
                parent: secondaryAnimation,
                curve: Curves.easeInOutCubic,
              ),
            );
        return SlideTransition(
          position: leaving,
          child: SlideTransition(position: entering, child: child),
        );
      },
    );
  }
}
