import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// Viewer-side only: every setting applied here is one the controlled side
// already accepts from any viewer, so peers need no update.
const String _kPeerOptionLowBandwidthMode = 'low-bandwidth-mode';
const String _kPeerOptionLowBandwidthRestore = 'low-bandwidth-mode-restore';
const int _kLowBandwidthQuality = 10;
const int _kLowBandwidthFps = 10;
// Hardware H264/H265 are given 1.5-2x the bitrate at low ratios (hwcodec.rs
// calc_bitrate); VP8 keeps the software target and encodes fastest.
const String _kLowBandwidthCodec = 'vp8';
const String _kOptionDisableAudio = 'disable-audio';
const String _kOptionI444 = 'i444';

TToggleMenu toolbarLowBandwidthMode(FFI ffi) {
  final sessionId = ffi.sessionId;
  return TToggleMenu(
      value: bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: _kPeerOptionLowBandwidthMode),
      onChanged: (value) async {
        if (value == null) return;
        if (value) {
          await _enableLowBandwidthMode(sessionId);
        } else {
          await _disableLowBandwidthMode(sessionId);
        }
      },
      child: Text(translate('Low bandwidth mode')));
}

Future<void> _enableLowBandwidthMode(SessionID sessionId) async {
  final customQuality =
      await bind.sessionGetCustomImageQuality(sessionId: sessionId);
  final restore = {
    'image-quality':
        await bind.sessionGetImageQuality(sessionId: sessionId) ?? '',
    'custom-image-quality': (customQuality != null && customQuality.isNotEmpty)
        ? customQuality[0]
        : null,
    'custom-fps':
        await bind.sessionGetOption(sessionId: sessionId, arg: 'custom-fps') ??
            '',
    'codec-preference': await bind.sessionGetOption(
            sessionId: sessionId, arg: kOptionCodecPreference) ??
        '',
    'disable-audio': bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: _kOptionDisableAudio),
    'i444': bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: _kOptionI444),
  };
  await bind.sessionPeerOption(
      sessionId: sessionId,
      name: _kPeerOptionLowBandwidthRestore,
      value: jsonEncode(restore));
  await bind.sessionPeerOption(
      sessionId: sessionId, name: _kPeerOptionLowBandwidthMode, value: 'Y');

  await bind.sessionSetCustomImageQuality(
      sessionId: sessionId, value: _kLowBandwidthQuality);
  await bind.sessionSetCustomFps(sessionId: sessionId, fps: _kLowBandwidthFps);
  await _setToggle(sessionId, _kOptionDisableAudio, true);
  await _setToggle(sessionId, _kOptionI444, false);
  await bind.sessionPeerOption(
      sessionId: sessionId,
      name: kOptionCodecPreference,
      value: _kLowBandwidthCodec);
  bind.sessionChangePreferCodec(sessionId: sessionId);
}

Future<void> _disableLowBandwidthMode(SessionID sessionId) async {
  await bind.sessionPeerOption(
      sessionId: sessionId, name: _kPeerOptionLowBandwidthMode, value: '');
  Map<String, dynamic> restore = {};
  try {
    restore = jsonDecode(await bind.sessionGetPeerOption(
        sessionId: sessionId, name: _kPeerOptionLowBandwidthRestore));
  } catch (e) {
    debugPrint('Low bandwidth mode: no settings to restore, $e');
    return;
  }
  await bind.sessionPeerOption(
      sessionId: sessionId, name: _kPeerOptionLowBandwidthRestore, value: '');

  final customQuality = restore['custom-image-quality'];
  if (customQuality is int) {
    await bind.sessionSetCustomImageQuality(
        sessionId: sessionId, value: customQuality);
  }
  final imageQuality = restore['image-quality'];
  if (imageQuality is String &&
      imageQuality.isNotEmpty &&
      imageQuality != kRemoteImageQualityCustom) {
    await bind.sessionSetImageQuality(
        sessionId: sessionId, value: imageQuality);
  }
  final customFps = restore['custom-fps'];
  if (customFps is String) {
    await bind.sessionSetCustomFps(
        sessionId: sessionId, fps: int.tryParse(customFps) ?? 30);
    // Put back the exact stored value, including "unset".
    await bind.sessionPeerOption(
        sessionId: sessionId, name: 'custom-fps', value: customFps);
  }
  final disableAudio = restore['disable-audio'];
  if (disableAudio is bool) {
    await _setToggle(sessionId, _kOptionDisableAudio, disableAudio);
  }
  final i444 = restore['i444'];
  if (i444 is bool) {
    await _setToggle(sessionId, _kOptionI444, i444);
  }
  final codec = restore['codec-preference'];
  if (codec is String) {
    await bind.sessionPeerOption(
        sessionId: sessionId, name: kOptionCodecPreference, value: codec);
  }
  bind.sessionChangePreferCodec(sessionId: sessionId);
}

Future<void> _setToggle(SessionID sessionId, String option, bool on) async {
  if (bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option) !=
      on) {
    await bind.sessionToggleOption(sessionId: sessionId, value: option);
  }
}
