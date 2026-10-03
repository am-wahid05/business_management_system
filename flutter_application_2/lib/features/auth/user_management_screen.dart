import 'package:flutter/material.dart';

import 'auth_models.dart';
import 'auth_repository.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({required this.repository, super.key});

  final AuthRepository repository;

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late Future<List<AppUser>> _users;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _users = widget.repository.allUsers();

  Future<void> _addUser() async {
    if (!(widget.repository.currentUser?.can(AppPermission.manageUsers) ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only an administrator can create users')));
      return;
    }
    final result = await showDialog<_NewUser>(context: context, builder: (_) => const _NewUserDialog());
    if (result == null) return;
    try {
      await widget.repository.createUser(username: result.username, displayName: result.displayName, role: result.role, password: result.password);
      setState(_reload);
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create user: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addUser, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add user')),
      body: FutureBuilder<List<AppUser>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Could not load users: ${snapshot.error}'));
          return ListView(padding: const EdgeInsets.all(24), children: [Text('Users', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 16), ...snapshot.data!.map((user) => Card(child: ListTile(leading: Icon(user.role == UserRole.admin ? Icons.admin_panel_settings_outlined : Icons.badge_outlined), title: Text(user.displayName), subtitle: Text('${user.username} · ${user.role.name} · ${user.isActive ? 'Active' : 'Inactive'}'))))]);
        },
      ),
    );
  }
}

class _NewUser {
  const _NewUser({required this.username, required this.displayName, required this.password, required this.role});

  final String username;
  final String displayName;
  final String password;
  final UserRole role;
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.secretary;

  @override
  void dispose() { _username.dispose(); _displayName.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add user'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _displayName, decoration: const InputDecoration(labelText: 'Display name')), TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')), DropdownButtonFormField<UserRole>(initialValue: _role, items: UserRole.values.map((role) => DropdownMenuItem(value: role, child: Text(role.name))).toList(), onChanged: (value) => setState(() => _role = value!)), TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password'))])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, _NewUser(username: _username.text, displayName: _displayName.text, password: _password.text, role: _role)), child: const Text('Create user'))],
      );
}