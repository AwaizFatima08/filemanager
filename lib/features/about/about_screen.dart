import 'package:flutter/material.dart';

import '../../ads/ads.dart';
import '../../app/services.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.services});
  final Services services;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _privacyRequired = false;

  @override
  void initState() {
    super.initState();
    widget.services.ads.privacyOptionsRequired.then((v) {
      if (mounted) setState(() => _privacyRequired = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.folder_copy, size: 64, color: t.colorScheme.primary),
          const SizedBox(height: 12),
          Text('File Manager', style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
          Text('Version $kAppVersion · by HomiLabs', textAlign: TextAlign.center, style: t.textTheme.bodySmall),
          const SizedBox(height: 24),
          const Text(
            'Browse the folders on your phone, sort and group files, and copy, move, '
            'rename, delete or share them.\n\n'
            'Tips:\n'
            '• Long-press a file to select several at once.\n'
            '• Tap ⋮ next to any file for all its options.\n'
            '• Use the sort button to sort by name, date, size or type, and to group files into sections.\n\n'
            'Your files never leave your phone unless you share them.',
          ),
          if (_privacyRequired) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.services.ads.showPrivacyOptions,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Ad privacy options'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: AdBannerSlot(ads: widget.services.ads, placement: AdPlacement.aboutBanner),
      ),
    );
  }
}
