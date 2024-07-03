import "dart:async";
import "dart:io";
import "dart:math";

import 'package:flutter/material.dart';
import "package:flutter_animate/flutter_animate.dart";
import 'package:logging/logging.dart';
import "package:photos/core/configuration.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import 'package:photos/ui/tools/app_lock.dart';
import 'package:photos/utils/auth_util.dart';
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/lockscreen_setting.dart";

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _logger = Logger("LockScreen");
  bool _isShowingLockScreen = false;
  bool _hasPlacedAppInBackground = false;
  bool _hasAuthenticationFailed = false;
  int? lastAuthenticatingTime;
  bool isTimerRunning = false;
  int lockedTime = 0;
  int invalidAttemptCount = 0;
  int remainingTime = 0;
  final _lockscreenSetting = LockscreenSetting.instance;

  @override
  void initState() {
    _logger.info("initiatingState");
    super.initState();
    invalidAttemptCount = _lockscreenSetting.getInvalidAttemptCount();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (isNonMobileIOSDevice()) {
        _logger.info('ignore init for non mobile iOS device');
        return;
      }
      _showLockScreen(source: "postFrameInit");
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: ExactAssetImage(
              'assets/loading_photos_background_fullscreen.png',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                height: 120,
                width: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Colors.grey.shade500.withOpacity(0.2),
                            Colors.grey.shade50.withOpacity(0.1),
                            Colors.grey.shade400.withOpacity(0.2),
                            Colors.grey.shade300.withOpacity(0.4),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorTheme.backgroundBase,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 75,
                      width: 75,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: calculateRemainingTime(),
                        ),
                        curve: Curves.ease,
                        duration: const Duration(milliseconds: 50),
                        builder: (context, value, _) =>
                            CircularProgressIndicator(
                          backgroundColor: colorTheme.fillFaintPressed,
                          value: value,
                          color: colorTheme.primary400,
                          strokeWidth: 1.5,
                        ),
                      ),
                    ),
                    IconButtonWidget(
                      size: 30,
                      icon: Icons.lock,
                      iconButtonType: IconButtonType.primary,
                      iconColor: colorTheme.tabIcon,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              isTimerRunning
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          "Too many incorrect attempts",
                          style: textTheme.body,
                        )
                            .animate(delay: const Duration(milliseconds: 2000))
                            .fadeOut(duration: 400.ms),
                        Text(
                          formatTime(remainingTime),
                          style: textTheme.body,
                        )
                            .animate(delay: const Duration(milliseconds: 2250))
                            .fadeIn(duration: 400.ms),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => _showLockScreen(source: "tap"),
                      child: Text(
                        "Tap to unlock",
                        style: textTheme.body,
                      ),
                    ),
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool isNonMobileIOSDevice() {
    if (Platform.isAndroid) {
      return false;
    }
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide > 600 ? true : false;
  }

  Future<void> _autoLogoutOnMaxInvalidAttempts() async {
    final AlertDialog alert = AlertDialog(
      title: const Text("Too many incorrect attempts"),
      content: Text(S.of(context).pleaseLoginAgain),
      actions: [
        TextButton(
          child: Text(
            S.of(context).ok,
            style: TextStyle(
              color: Theme.of(context).colorScheme.greenAlternative,
            ),
          ),
          onPressed: () async {
            Navigator.of(context, rootNavigator: true).pop('dialog');
            Navigator.of(context).popUntil((route) => route.isFirst);
            final dialog =
                createProgressDialog(context, S.of(context).loggingOut);
            await dialog.show();
            await Configuration.instance.logout();
            await dialog.hide();
          },
        ),
      ],
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    _logger.info(state.toString());
    if (state == AppLifecycleState.resumed && !_isShowingLockScreen) {
      _hasPlacedAppInBackground = false;
      final bool didAuthInLast5Seconds = lastAuthenticatingTime != null &&
          DateTime.now().millisecondsSinceEpoch - lastAuthenticatingTime! <
              5000;

      if (!_hasAuthenticationFailed && !didAuthInLast5Seconds) {
        if (_lockscreenSetting.getlastInvalidAttemptTime() >
                DateTime.now().millisecondsSinceEpoch &&
            !_isShowingLockScreen) {
          final int time = (_lockscreenSetting.getlastInvalidAttemptTime() -
                  DateTime.now().millisecondsSinceEpoch) ~/
              1000;

          Future.delayed(
            Duration.zero,
            () {
              startLockTimer(time);
              _showLockScreen(source: "lifeCycle");
            },
          );
        }
      } else {
        _hasAuthenticationFailed = false;
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_isShowingLockScreen) {
        _hasPlacedAppInBackground = true;
        _hasAuthenticationFailed = false;
      }
    }
  }

  @override
  void dispose() {
    _logger.info('disposing');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> startLockTimer(int time) async {
    if (isTimerRunning) {
      return;
    }

    setState(() {
      isTimerRunning = true;
      remainingTime = time;
    });

    while (remainingTime > 0) {
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        remainingTime--;
      });
    }

    setState(() {
      isTimerRunning = false;
    });
  }

  double calculateRemainingTime() {
    final int totalLockedTime =
        lockedTime = pow(2, invalidAttemptCount - 5).toInt() * 30;
    if (remainingTime == 0) return 1;

    return 1 - remainingTime / totalLockedTime;
  }

  String formatTime(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int remainingSeconds = seconds % 60;

    if (hours > 0) {
      return "${hours}h ${minutes}m";
    } else if (minutes > 0) {
      return "${minutes}m ${remainingSeconds}s";
    } else {
      return "${remainingSeconds}s";
    }
  }

  Future<void> _showLockScreen({String source = ''}) async {
    final int id = DateTime.now().millisecondsSinceEpoch;
    _logger.info("Showing lock screen $source $id");
    try {
      if (id < _lockscreenSetting.getlastInvalidAttemptTime() &&
          !_isShowingLockScreen) {
        final int time =
            (_lockscreenSetting.getlastInvalidAttemptTime() - id) ~/ 1000;

        await startLockTimer(time);
      }
      _isShowingLockScreen = true;
      final result = isTimerRunning
          ? false
          : await requestAuthentication(
              context,
              context.l10n.authToViewYourMemories,
              isLockscreenAuth: true,
            );
      _logger.finest("LockScreen Result $result $id");
      _isShowingLockScreen = false;
      if (result) {
        lastAuthenticatingTime = DateTime.now().millisecondsSinceEpoch;
        AppLock.of(context)!.didUnlock();
        await _lockscreenSetting.setInvalidAttemptCount(0);
        setState(() {
          lockedTime = 15;
          isTimerRunning = false;
        });
      } else {
        if (!_hasPlacedAppInBackground) {
          if (_lockscreenSetting.getInvalidAttemptCount() > 4 &&
              invalidAttemptCount !=
                  _lockscreenSetting.getInvalidAttemptCount()) {
            invalidAttemptCount = _lockscreenSetting.getInvalidAttemptCount();

            if (invalidAttemptCount > 9) {
              await _autoLogoutOnMaxInvalidAttempts();
              return;
            }

            lockedTime = pow(2, invalidAttemptCount - 5).toInt() * 30;
            await _lockscreenSetting.setLastInvalidAttemptTime(
              DateTime.now().millisecondsSinceEpoch + lockedTime * 1000,
            );
            await startLockTimer(lockedTime);
          }
          _hasAuthenticationFailed = true;
          _logger.info("Authentication failed");
        }
      }
    } catch (e, s) {
      _isShowingLockScreen = false;
      _logger.severe(e, s);
    }
  }
}
