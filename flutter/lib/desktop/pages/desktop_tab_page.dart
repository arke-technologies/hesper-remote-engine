import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/hesper_relays.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(
              controller: tabController,
              // Hesper Remote: top-right status pill (relay + service readiness)
              // followed by the Settings action.
              tail: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _HesperStatusPill(),
                  Offstage(
                    offstage:
                        bind.isIncomingOnly() || bind.isDisableSettings(),
                    child: ActionIcon(
                      message: 'Settings',
                      icon: IconFont.menu,
                      onTap: DesktopTabPage.onAddSetting,
                      isClose: false,
                    ),
                  ),
                ],
              ),
            )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}

// Hesper Remote: top-right window-chrome status pill AND relay switcher. A small
// status dot + "Ready · <relay>" on a pale-violet pill (hard corners). The dot
// colour + leading word track the live service status (stateGlobal.svcStatus).
// Tapping the pill opens a menu of the relays in `kHesperRelays`; choosing a relay
// outside the home jurisdiction (ZA) raises a data-sovereignty consent first. The
// chosen relay persists via the `custom-rendezvous-server` option.
class _HesperStatusPill extends StatefulWidget {
  const _HesperStatusPill();

  @override
  State<_HesperStatusPill> createState() => _HesperStatusPillState();
}

class _HesperStatusPillState extends State<_HesperStatusPill> {
  static const Color _green = kHesperBrand;
  static const Color _warn = Color(0xFFE0A312);

  Future<void> _onSelect(HesperRelay relay) async {
    final changed = await switchHesperRelay(gFFI.dialogManager, relay);
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = currentHesperRelay();
    return Obx(() {
      final status = stateGlobal.svcStatus.value;
      final bool ready = status == SvcStatus.ready;
      final bool connecting = status == SvcStatus.connecting;
      final Color dot = ready
          ? _green
          : (connecting ? _warn : const Color(0xFFAAA5B7));
      final String statusWord = ready
          ? translate('Ready')
          : (connecting
              ? translate('connecting_status')
              : translate('not_ready_status'));
      final Color pillBg = hesperBrandPale(context);
      final Color pillInk = hesperInkBody(context);
      return PopupMenuButton<HesperRelay>(
        tooltip: 'Switch relay',
        position: PopupMenuPosition.under,
        onSelected: _onSelect,
        itemBuilder: (context) => kHesperRelays
            .map((r) => PopupMenuItem<HesperRelay>(
                  value: r,
                  child: Row(
                    children: [
                      Icon(r.id == current.id ? Icons.check : Icons.public,
                          size: 16, color: pillInk),
                      const SizedBox(width: 8),
                      Text(r.label),
                      if (r.region != kHesperHomeRegion) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.flight_takeoff, size: 13, color: _warn),
                      ],
                    ],
                  ),
                ))
            .toList(),
        child: Container(
          margin: const EdgeInsets.only(left: 8, right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  '$statusWord · ${current.label}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kHesperBodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: pillInk,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 16, color: pillInk),
            ],
          ),
        ),
      );
    });
  }
}
