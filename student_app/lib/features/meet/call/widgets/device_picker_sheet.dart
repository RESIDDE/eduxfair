import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../call_provider.dart';

/// Microphone, camera and speaker, switched live.
///
/// Labels are blank until a permission has been granted at least once — a
/// platform rule rather than something to work around — so an unlabelled entry
/// falls back to a short form of its id instead of an empty row.
void showDevicePickerSheet(BuildContext context, CallProvider call) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _DevicePicker(call: call),
  );
}

class _DevicePicker extends StatefulWidget {
  final CallProvider call;
  const _DevicePicker({required this.call});

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  List<MediaDevice> _devices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final found = await widget.call.devices();
    if (!mounted) return;
    setState(() {
      _devices = found;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const groups = {
      'audioinput': 'Microphone',
      'videoinput': 'Camera',
      'audiooutput': 'Speaker',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Devices',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_devices.isEmpty)
                    const Text(
                      'No devices listed yet. Allow the camera and microphone '
                      'and they will appear.',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  for (final entry in groups.entries) ...[
                    if (_devices.any((d) => d.kind == entry.key)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Text(
                          entry.value.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      for (final device
                          in _devices.where((d) => d.kind == entry.key))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            device.label.isNotEmpty
                                ? device.label
                                : '${entry.value} '
                                    '${device.deviceId.characters.take(6)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                          onTap: () async {
                            await widget.call.selectDevice(device);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
