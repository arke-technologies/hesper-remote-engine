// Hesper Remote — the relay catalog + switch logic.
//
// TO ADD A RELAY IN FUTURE: append a `HesperRelay` to `kHesperRelays` with a
// stable `id`, a user-facing `label`, the rendezvous/relay `host`, and its
// `region` + `regionName`. It then appears automatically in the top-right
// status-pill menu (desktop_tab_page.dart). Choosing a relay whose `region`
// differs from `kHesperHomeRegion` raises a data-sovereignty consent before the
// switch is applied. All relays share the baked hbbs key (RS_PUB_KEY in
// libs/hbb_common/src/config.rs), so there is no per-relay key here.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class HesperRelay {
  final String id;
  final String label;
  final String host; // rendezvous + relay host (hbbs/hbbr share it)
  final String region; // short code, e.g. 'ZA', 'EU'
  final String regionName; // human name, e.g. 'South Africa', 'Europe'
  const HesperRelay({
    required this.id,
    required this.label,
    required this.host,
    required this.region,
    required this.regionName,
  });
}

/// The user's home jurisdiction. Switching to a relay outside it triggers the
/// data-sovereignty consent.
const String kHesperHomeRegion = 'ZA';

/// The relay catalog. APPEND new relays here — each appears in the pill menu,
/// with sovereignty consent applied automatically when `region != home`.
const List<HesperRelay> kHesperRelays = <HesperRelay>[
  HesperRelay(
    id: 'za-artemis',
    label: 'Hesper Relay (ZA)',
    host: '102.214.9.70',
    region: 'ZA',
    regionName: 'South Africa',
  ),
  HesperRelay(
    id: 'eu-netcup',
    label: 'Hesper Relay (EU)',
    host: '159.195.16.230',
    region: 'EU',
    regionName: 'Europe',
  ),
];

HesperRelay get _defaultHesperRelay => kHesperRelays.firstWhere(
    (r) => r.region == kHesperHomeRegion,
    orElse: () => kHesperRelays.first);

/// The relay currently in effect — derived from the persisted
/// `custom-rendezvous-server` option, falling back to the home relay.
HesperRelay currentHesperRelay() {
  final host = bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim();
  if (host.isEmpty) return _defaultHesperRelay;
  return kHesperRelays.firstWhere((r) => r.host == host,
      orElse: () => _defaultHesperRelay);
}

/// Point the client at [relay]: set the rendezvous + relay server options
/// (persisted) so this machine's registration and future connections use it.
Future<void> _applyHesperRelay(HesperRelay relay) async {
  await bind.mainSetOption(key: 'custom-rendezvous-server', value: relay.host);
  await bind.mainSetOption(key: 'relay-server', value: relay.host);
}

/// Switch to [relay], raising a data-sovereignty consent first when it is
/// outside the home jurisdiction. Returns true if the switch was applied.
Future<bool> switchHesperRelay(
    OverlayDialogManager dialogManager, HesperRelay relay) async {
  if (relay.id == currentHesperRelay().id) return false;
  if (relay.region != kHesperHomeRegion) {
    final consented = await _confirmSovereignty(dialogManager, relay);
    if (!consented) return false;
  }
  await _applyHesperRelay(relay);
  showToast('Relay set to ${relay.label}. Reconnect to apply.');
  return true;
}

Future<bool> _confirmSovereignty(
    OverlayDialogManager dialogManager, HesperRelay relay) async {
  final res = await dialogManager.show<bool>((setState, close, context) {
    return CustomAlertDialog(
      title: Row(children: [
        const Icon(Icons.public, color: Color(0xFFE0A312)),
        const SizedBox(width: 10),
        Expanded(child: Text('Data sovereignty — ${relay.regionName}')),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(
          'Switching to the ${relay.regionName} relay routes your remote-session '
          'traffic through a server outside South Africa. Your session data — '
          'screen, keystrokes, clipboard and any transferred files — will transit '
          '${relay.regionName}. The session stays end-to-end encrypted and Hesper '
          'does not store it, but under POPIA you are consenting to this '
          'cross-border transfer.\n\nKeep the South African relay unless you have '
          'a reason to switch.',
          style: const TextStyle(height: 1.4),
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: () => close(false), isOutline: true),
        dialogButton('I consent, switch', onPressed: () => close(true)),
      ],
      onCancel: () => close(false),
    );
  });
  return res == true;
}
