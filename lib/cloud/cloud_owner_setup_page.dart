import 'package:flutter/material.dart';

import 'supabase_service.dart';

class CloudOwnerSetupPage extends StatefulWidget {
  const CloudOwnerSetupPage({super.key});

  @override
  State<CloudOwnerSetupPage> createState() => _CloudOwnerSetupPageState();
}

class _CloudOwnerSetupPageState extends State<CloudOwnerSetupPage> {
  final _emailController = TextEditingController(text: 'tlcsystem26@gmail.com');
  final _passwordController = TextEditingController();

  static const String _expectedUserId = '13be2536-c081-4cd0-9d59-0f3190b63219';

  static const String _schoolName = 'THE LEARNING CIRCLE SECONDARY SCHOOL';

  static const String _schoolSlug = 'the-learning-circle-secondary-school';

  bool _loading = false;
  bool _hidePassword = true;
  String _message = 'Sign in with the Supabase cloud owner account.';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _setupCloudSchool() async {
    final client = SupabaseService.client;

    if (client == null) {
      setState(() {
        _message = 'Supabase is not initialized. Check your internet connection and app configuration.';
      });
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Enter the cloud owner email and password.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = 'Signing in securely...';
    });

    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw Exception('Supabase did not return a signed-in user.');
      }

      if (user.id != _expectedUserId) {
        await client.auth.signOut();
        throw Exception(
          'The signed-in account UID does not match the approved cloud owner UID. '
          'No school was created.',
        );
      }

      if (!mounted) return;

      setState(() {
        _message = 'Owner verified. Checking for an existing school...';
      });

      // Prevent accidental duplicate creation if setup is repeated.
      final existing = await client
          .from('schools')
          .select('id, name, slug, created_by')
          .eq('slug', _schoolSlug)
          .maybeSingle();

      if (existing != null) {
        if (existing['created_by'] != user.id) {
          throw Exception(
            'This school slug belongs to another owner. '
            'No changes were made.',
          );
        }

        final membership = await client
            .from('school_memberships')
            .select('id, role, is_active')
            .eq('school_id', existing['id'])
            .eq('user_id', user.id)
            .maybeSingle();

        if (membership == null ||
            membership['role'] != 'owner' ||
            membership['is_active'] != true) {
          throw Exception(
            'The school exists, but its active owner membership '
            'could not be verified. No changes were made.',
          );
        }

        if (!mounted) return;

        setState(() {
          _message =
              'CLOUD OWNER VERIFIED SUCCESSFULLY!\n\n'
              'School: $_schoolName\n'
              'School ID: ${existing['id']}\n'
              'Owner: ${user.email}\n'
              'Membership: ${membership['role']}\n'
              'Status: Active\n\n'
              'No student or fee records were uploaded.';
        });

        return;
      }

      setState(() {
        _message = 'Creating the TLC cloud school...';
      });

      final schoolId = await client.rpc(
        'create_school',
        params: {'p_name': _schoolName, 'p_slug': _schoolSlug},
      );

      if (!mounted) return;

      setState(() {
        _message =
            'SUCCESS! The cloud school has been created.\n\n'
            'School: $_schoolName\n'
            'School ID: $schoolId\n'
            'Owner: $email\n\n'
            'No student or fee records were uploaded.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _message = 'Setup could not be completed:\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('TLC Cloud Owner Setup'),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              color: Colors.white,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.cloud_done,
                      color: Color(0xFFB71C1C),
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Create TLC Cloud School',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This is a one-time cloud owner setup. '
                      'Your local school records will not be uploaded.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Cloud owner email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Cloud owner password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _hidePassword = !_hidePassword;
                            });
                          },
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _loading ? null : _setupCloudSchool,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                        _loading ? 'Please wait...' : 'Verify & Create School',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB71C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    SelectableText(
                      _message,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
