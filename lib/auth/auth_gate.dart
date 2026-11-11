import 'package:flutter/material.dart';

import 'auth_repository.dart';
import '../school_profile.dart';
import 'app_user.dart';

typedef AuthenticatedHomeBuilder = Widget Function(
  AppUser user,
  VoidCallback onSignOut,
  AuthRepository repository,
);

class AuthGate extends StatefulWidget {
  final SchoolProfile profile;
  final AuthenticatedHomeBuilder homeBuilder;
  final AuthRepository? repository;

  const AuthGate({
    super.key,
    required this.profile,
    required this.homeBuilder,
    this.repository,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthRepository _repository =
      widget.repository ?? SqliteAuthRepository();
  late Future<bool> _accountsExist;
  AppUser? _user;
  bool _setupComplete = false;

  @override
  void initState() {
    super.initState();
    _accountsExist = _repository.hasAccounts();
  }

  void _refreshSetup() => setState(() {
    _setupComplete = true;
  });

  void _signIn(AppUser user) => setState(() => _user = user);

  void _signOut() => setState(() => _user = null);

  @override
  Widget build(BuildContext context) {
    final signedIn = _user;
    if (signedIn != null) {
      return widget.homeBuilder(signedIn, _signOut, _repository);
    }
    if (_setupComplete) {
      return LoginPage(
        repository: _repository,
        profile: widget.profile,
        onSignedIn: _signIn,
        setupMessage: 'Administrator account created. Sign in to continue.',
      );
    }

    return FutureBuilder<bool>(
      future: _accountsExist,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AuthLoadingError(
            error: snapshot.error!,
            onRetry: () => setState(() {
              _accountsExist = _repository.hasAccounts();
            }),
          );
        }
        if (!snapshot.hasData) {
          return const _AuthLoading();
        }
        if (!snapshot.data!) {
          return InitialAdministratorPage(
            repository: _repository,
            profile: widget.profile,
            onCreated: _refreshSetup,
          );
        }
        return LoginPage(
          repository: _repository,
          profile: widget.profile,
          onSignedIn: _signIn,
        );
      },
    );
  }
}

class InitialAdministratorPage extends StatefulWidget {
  final AuthRepository repository;
  final SchoolProfile profile;
  final VoidCallback onCreated;

  const InitialAdministratorPage({
    super.key,
    required this.repository,
    required this.profile,
    required this.onCreated,
  });

  @override
  State<InitialAdministratorPage> createState() =>
      _InitialAdministratorPageState();
}

class _InitialAdministratorPageState extends State<InitialAdministratorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _working = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.repository.createInitialAdministrator(
        fullName: _nameController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );
      if (mounted) widget.onCreated();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not create the administrator account: $error';
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AuthPageFrame(
    profile: widget.profile,
    title: 'Create the first administrator',
    subtitle:
        'Set up the secure school account before using TLC School System.',
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('setup-full-name'),
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter the administrator name.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('setup-username'),
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.account_circle_outlined),
            ),
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.trim().length < 3
                ? 'Use at least 3 characters.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('setup-password'),
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            obscureText: !_showPassword,
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.length < 10
                ? 'Use at least 10 characters.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('setup-password-confirmation'),
            controller: _confirmationController,
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _create(),
            validator: (value) => value != _passwordController.text
                ? 'Passwords do not match.'
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _AuthError(message: _error!),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _working ? null : _create,
            child: _working
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create administrator'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Passwords are stored as salted hashes, never as plain text.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF687080)),
          ),
        ],
      ),
    ),
  );
}

class LoginPage extends StatefulWidget {
  final AuthRepository repository;
  final SchoolProfile profile;
  final ValueChanged<AppUser> onSignedIn;
  final String? setupMessage;

  const LoginPage({
    super.key,
    required this.repository,
    required this.profile,
    required this.onSignedIn,
    this.setupMessage,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _working = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final user = await widget.repository.authenticate(
        _usernameController.text,
        _passwordController.text,
      );
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _error =
              'Username or password is incorrect, or this account is inactive.';
          _working = false;
        });
        return;
      }
      widget.onSignedIn(user);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Sign-in could not be completed: $error';
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AuthPageFrame(
    profile: widget.profile,
    title: 'Welcome back',
    subtitle: 'Sign in with your school account to continue.',
    child: AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.setupMessage != null) ...[
              _AuthNotice(message: widget.setupMessage!),
              const SizedBox(height: 14),
            ],
            TextFormField(
              key: const ValueKey('login-username'),
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.account_circle_outlined),
              ),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your username.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('login-password'),
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _signIn(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _AuthError(message: _error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _working ? null : _signIn,
              child: _working
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 14),
            Text(
              '${widget.profile.schoolName}  •  ${widget.profile.academicYear}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF687080), fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AuthPageFrame extends StatelessWidget {
  final SchoolProfile profile;
  final String title;
  final String subtitle;
  final Widget child;

  const _AuthPageFrame({
    required this.profile,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/backgrounds/login_wallpaper.jpeg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: Color(0xFFF5EEEE)),
          ),
          ColoredBox(color: Colors.white.withValues(alpha: 0.72)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF0D7D7)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/tlc_logo.png',
                        width: 76,
                        height: 76,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.school_rounded,
                          color: profile.primaryColor,
                          size: 62,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        profile.schoolName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: profile.primaryColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF252B36),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF687080),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Text(
              SchoolProfile.developerCreditText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFC62828),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  final String message;

  const _AuthError({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F0),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFF1CBCB)),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xFF9A2222), fontSize: 12),
    ),
  );
}

class _AuthNotice extends StatelessWidget {
  final String message;

  const _AuthNotice({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F8F4),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFD9E9D9)),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF345B36), fontSize: 12),
    ),
  );
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: Color(0xFFC62828))),
  );
}

class _AuthLoadingError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _AuthLoadingError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFC62828)),
              const SizedBox(height: 12),
              const Text(
                'The sign-in service could not be started.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    ),
  );
}
