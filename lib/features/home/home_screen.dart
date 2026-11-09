import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/storage.dart';
import '../about/about_screen.dart';
import '../browser/browser_screen.dart';

/// Start screen: storage volumes and shortcuts to common folders. Asks for
/// storage access first if the app does not have it yet.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});
  final Services services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool? _access;
  List<StorageRoot> _roots = const [];
  List<(String, String)> _quick = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The user grants "All files access" in system settings and comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final access = await hasStorageAccess();
    final roots = access ? await storageRoots() : const <StorageRoot>[];
    final quick = access ? await existingQuickFolders() : const <(String, String)>[];
    if (!mounted) return;
    setState(() {
      _access = access;
      _roots = roots;
      _quick = quick;
    });
  }

  void _open(String root, String start) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BrowserScreen(services: widget.services, root: root, start: start),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Manager'),
        actions: [
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => AboutScreen(services: widget.services))),
          ),
        ],
      ),
      body: switch (_access) {
        null => const Center(child: CircularProgressIndicator()),
        false => _AccessNeeded(
          onGrant: () async {
            if (await requestStorageAccess()) _refresh();
          },
        ),
        true => _body(context),
      },
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final r in _roots)
          Card(
            child: ListTile(
              leading: Icon(r.path == internalRoot ? Icons.smartphone : Icons.sd_card, size: 32),
              title: Text(r.label, style: t.textTheme.titleMedium),
              subtitle: Text(r.path),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(r.path, r.path),
            ),
          ),
        if (_quick.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('Quick folders', style: t.textTheme.titleSmall),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (path, label) in _quick)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(internalRoot, path),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_quickIcon(label), size: 32, color: t.colorScheme.primary),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  IconData _quickIcon(String label) => switch (label) {
    'Downloads' => Icons.download,
    'Camera' => Icons.photo_camera,
    'Pictures' => Icons.image,
    'Documents' => Icons.description,
    'Music' => Icons.music_note,
    'Videos' => Icons.movie,
    _ => Icons.folder,
  };
}

class _AccessNeeded extends StatelessWidget {
  const _AccessNeeded({required this.onGrant});
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Allow access to your files',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'To show, copy, move and share your files, File Manager needs "All files access". '
              'Your files stay on your phone.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onGrant, icon: const Icon(Icons.lock_open), label: const Text('Allow access')),
          ],
        ),
      ),
    );
  }
}
