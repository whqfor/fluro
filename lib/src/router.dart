/*
 * fluro
 * Created by Yakka
 * https://theyakka.com
 *
 * Copyright (c) 2019 Yakka, LLC. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';

import 'package:fluro/fluro.dart';
import 'package:fluro/src/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:get_it/get_it.dart';

// 全局 GetIt 实例,为了实现无context导航
class ServiceLocator {
  final GetIt getIt = GetIt();
  void setupLocator(){
    getIt.registerSingleton(NavigateService());
  }
}

class NavigateService {
  final GlobalKey<NavigatorState> key = GlobalKey(debugLabel: 'navigate_key');
  NavigatorState get navigator => key.currentState;
  get pushNamedG       => navigator.pushNamed;
  get pushG            => navigator.push;
  get pushReplacementG => navigator.pushReplacement;
  get popG             => navigator.pop;
  get popUntilG        => navigator.popUntil;
}

class Router {

  ServiceLocator serviceLocator = ServiceLocator();

  static final appRouter = new Router();

  /// The tree structure that stores the defined routes
  final RouteTree _routeTree = new RouteTree();

  /// Generic handler for when a route has not been defined
  Handler notFoundHandler;

  /// Creates a [PageRoute] definition for the passed [RouteHandler]. You can optionally provide a default transition type.
  void define(String routePath,
      {@required Handler handler, TransitionType transitionType}) {
    _routeTree.addRoute(
        new AppRoute(routePath, handler, transitionType: transitionType));
  }

  /// Finds a defined [AppRoute] for the path value. If no [AppRoute] definition was found
  /// then function will return null.
  AppRouteMatch match(String path) {
    return _routeTree.matchRoute(path);
  }

  bool pop<T extends Object>(BuildContext context, [ T result ]) {
    return serviceLocator.getIt<NavigateService>().popG(result);
  }

  void popUntil(BuildContext context, String path) {
    serviceLocator.getIt<NavigateService>().popUntilG(ModalRoute.withName(path));
  }

  void popSkip(BuildContext context, String skip) {
    serviceLocator.getIt<NavigateService>().popUntilG(
        (Route<dynamic> route) {
          bool routePredicate = !route.willHandlePopInternally
              && route is ModalRoute
              && Uri.parse(route.settings.name).host != skip;
          if (!routePredicate) { // 双重否定为肯定
            // 包含则 skip 出栈
            print('popSkip $skip -- ${route.settings.name}');
          }
          return routePredicate;
        }
    );
  }

  ///
  Future navigateTo(BuildContext context, String path,
      {bool replace = false,
        bool clearStack = false,
        TransitionType transition,
        Duration transitionDuration = const Duration(milliseconds: 250),
        RouteTransitionsBuilder transitionBuilder,
        Object arguments}) {

    String umpPath = path;
    if (umpPath.contains("?")) {
      var splitParam = umpPath.split("?");
      umpPath = splitParam[0];
    }
    RouteSettings userSettings = RouteSettings(name: umpPath, arguments: arguments);

    RouteMatch routeMatch = matchRoute(context, path,
        transitionType: transition,
        transitionsBuilder: transitionBuilder,
        transitionDuration: transitionDuration,
        routeSettings: userSettings);
    Route<dynamic> route = routeMatch.route;
    Completer completer = new Completer();
    Future future = completer.future;
    if (routeMatch.matchType == RouteMatchType.nonVisual) {
      completer.complete("Non visual route type.");
    } else {
      if (route == null && notFoundHandler != null) {
        route = _notFoundRoute(context, path);
      }
      if (route != null) {
        if (clearStack) {
          future =
              Navigator.pushAndRemoveUntil(context, route, (check) => false);
        } else {
          if (replace) {
            // Navigator.pushReplacement(context, route)
            future = serviceLocator.getIt<NavigateService>().pushReplacementG(route);
          } else {
            future = serviceLocator.getIt<NavigateService>().pushG(route);
          }
        }
        completer.complete();
      } else {
        String error = "No registered route was found to handle '$path'.";
        print(error);
        completer.completeError(RouteNotFoundException(error, path));
      }
    }

    return future;
  }

  ///
  Route<Null> _notFoundRoute(BuildContext context, String path) {
    RouteCreator<Null> creator =
        (RouteSettings routeSettings, Map<String, List<String>> parameters) {
      return new MaterialPageRoute<Null>(
          settings: routeSettings,
          builder: (BuildContext context) {
            return notFoundHandler.handlerFunc(
                context, parameters, routeSettings.arguments);
          });
    };
    return creator(new RouteSettings(name: path), null);
  }

  ///
  RouteMatch matchRoute(BuildContext buildContext, String path,
      {RouteSettings routeSettings,
        TransitionType transitionType,
        Duration transitionDuration = const Duration(milliseconds: 250),
        RouteTransitionsBuilder transitionsBuilder}) {
    RouteSettings settingsToUse = routeSettings;

    print('routeSettings   --------- $routeSettings');
    if (routeSettings == null) {
      settingsToUse = new RouteSettings(name: path);
    }
    AppRouteMatch match = _routeTree.matchRoute(path);
    AppRoute route = match?.route;
    Handler handler = (route != null ? route.handler : notFoundHandler);
    var transition = transitionType;
    if (transitionType == null) {
      transition = route != null ? route.transitionType : TransitionType.native;
    }
    if (route == null && notFoundHandler == null) {
      return new RouteMatch(
          matchType: RouteMatchType.noMatch,
          errorMessage: "No matching route was found");
    }
    Map<String, List<String>> parameters =
        match?.parameters ?? <String, List<String>>{};
    if (handler.type == HandlerType.function) {
      handler.handlerFunc(buildContext, parameters, routeSettings.arguments);
      return new RouteMatch(matchType: RouteMatchType.nonVisual);
    }

    RouteCreator creator =
        (RouteSettings routeSettings, Map<String, List<String>> parameters) {
      bool isNativeTransition = (transition == TransitionType.native ||
          transition == TransitionType.nativeModal);
      if (isNativeTransition) {
        if (Platform.isIOS) {
          return new CupertinoPageRoute<dynamic>(
              settings: routeSettings,
              fullscreenDialog: transition == TransitionType.nativeModal,
              builder: (BuildContext context) {
                return handler.handlerFunc(
                    context, parameters, routeSettings.arguments);
              });
        } else if (transition == TransitionType.cupertino ||
            transition == TransitionType.cupertinoFullScreenDialog) {
          return new CupertinoPageRoute<dynamic>(
              settings: routeSettings,
              fullscreenDialog:
              transition == TransitionType.cupertinoFullScreenDialog,
              builder: (BuildContext context) {
                return handler.handlerFunc(
                    context, parameters, routeSettings.arguments);
              });
        } else {
          return new MaterialPageRoute<dynamic>(
              settings: routeSettings,
              fullscreenDialog: transition == TransitionType.nativeModal,
              builder: (BuildContext context) {
                return handler.handlerFunc(
                    context, parameters, routeSettings.arguments);
              });
        }
      } else {
        var routeTransitionsBuilder;
        if (transition == TransitionType.custom) {
          routeTransitionsBuilder = transitionsBuilder;
        } else {
          routeTransitionsBuilder = _standardTransitionsBuilder(transition);
        }
        return new PageRouteBuilder<dynamic>(
          settings: routeSettings,
          pageBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondaryAnimation) {
            return handler.handlerFunc(
                context, parameters, routeSettings.arguments);
          },
          transitionDuration: transitionDuration,
          transitionsBuilder: routeTransitionsBuilder,
        );
      }
    };
    return new RouteMatch(
      matchType: RouteMatchType.visual,
      route: creator(settingsToUse, parameters),
    );
  }

  RouteTransitionsBuilder _standardTransitionsBuilder(
      TransitionType transitionType) {
    return (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation, Widget child) {
      if (transitionType == TransitionType.fadeIn) {
        return new FadeTransition(opacity: animation, child: child);
      } else {
        const Offset topLeft = const Offset(0.0, 0.0);
        const Offset topRight = const Offset(1.0, 0.0);
        const Offset bottomLeft = const Offset(0.0, 1.0);
        Offset startOffset = bottomLeft;
        Offset endOffset = topLeft;
        if (transitionType == TransitionType.inFromLeft) {
          startOffset = const Offset(-1.0, 0.0);
          endOffset = topLeft;
        } else if (transitionType == TransitionType.inFromRight) {
          startOffset = topRight;
          endOffset = topLeft;
        }

        return new SlideTransition(
          position: new Tween<Offset>(
            begin: startOffset,
            end: endOffset,
          ).animate(animation),
          child: child,
        );
      }
    };
  }

  /// Route generation method. This function can be used as a way to create routes on-the-fly
  /// if any defined handler is found. It can also be used with the [MaterialApp.onGenerateRoute]
  /// property as callback to create routes that can be used with the [Navigator] class.
  Route<dynamic> generator(RouteSettings routeSettings) {
    RouteMatch match =
    matchRoute(null, routeSettings.name, routeSettings: routeSettings);
    return match.route;
  }

  /// Prints the route tree so you can analyze it.
  void printTree() {
    _routeTree.printTree();
  }
}
