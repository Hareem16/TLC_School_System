import 'package:flutter/material.dart';

import '../auth/app_user.dart';
import 'cloud_account_link_service.dart';
import 'supabase_service.dart';

class CloudAccountLinkPage extends StatefulWidget {
  final AppUser localUser;
  final Color primaryColor;

  const CloudAccountLinkPage({
    super.key,
    required this.localUser,
    required this.primaryColor,
  });

  @override
  State<CloudAccountLinkPage> createState() => _CloudAccountLinkPageState();
}

class _CloudAccountLinkPageState extends State<CloudAccountLinkPage> {
  final _passwordController = TextEditingController();
  bool _working = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _working = true;
      _message = null;
      _success = false;
    });
    try {
      final result = await CloudAccountLinkService.link(
        localUser: widget.localUser,
        cloudPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _success = result.device.status == 'approved';
        _message = result.device.status == 'approved'
            ? 'Cloud account connected. This device is approved.'
            : result.device.status == 'pending'
                ? 'Cloud account verified. This device is waiting for Admin approval.'
                : 'This device is blocked. Contact the Admin or Principal.';
        _passwordController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _working = true);
    try {
      await CloudAccountLinkService.disconnect();
      if (!mounted) return;
      setState(() {
        _message = 'Cloud session disconnected. Local offline login is unchanged.';
        _success = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = CloudAccountLinkService.isConnected;
    final cloudAvailable = SupabaseService.isInitialized;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.cloud_sync, size: 48, color: widget.primaryColor),
                  const SizedBox(height: 12),
                  const Text(
                    'Cloud Account & Device',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Local account: \${widget.localUser.fullName} (\${widget.localUser.role})',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.localUser.username,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  if (!cloudAvailable)
                    const _InfoLine(
                      icon: Icons.cloud_off,
                      text: 'Cloud is unavailable. The school app continues in offline mode.',
                    )
                  else if (connected) ...[
                    _InfoLine(
                      icon: Icons.cloud_done,
                      text: 'Connected cloud identity: \${CloudAccountLinkService.connectedEmail ?? ''}',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _working ? null : _disconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect cloud session'),
                    ),
                  ] else ...[
                    const _InfoLine(
                      icon: Icons.verified_user_outlined,
                      text: 'Use the separate Supabase cloud password for the same school email. Your local password is not sent to the cloud.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      enabled: !_working && cloudAvailable,
                      onSubmitted: (_) => _connect(),
                      decoration: const InputDecoration(
                        labelText: 'Cloud account password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _working || !cloudAvailable ? null : _connect,
                      icon: _working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_done),
                      label: Text(_working ? 'Connecting...' : 'Verify & connect device'),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    _InfoLine(
                      icon: _success ? Icons.check_circle : Icons.info_outline,
                      text: _message!,
                      color: _success ? Colors.green : null,
                    ),
                  ],
                  const Divider(height: 32),
                  const Text('Important', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'The cloud account must already exist and have an active TLC school membership assigned by an Admin. A newly registered device remains pending until an Admin approves it. Teacher, parent and student data synchronization stays disabled until their class and student access scopes are configured.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoLine({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color ?? Theme.of(context).colorScheme.primary, size: 21),
      const SizedBox(width: 10),
      Expanded(child: Text(text)),
    ],
  );
}
