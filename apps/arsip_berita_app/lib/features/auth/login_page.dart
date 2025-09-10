import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signInOrUp() async {
    setState(() { _loading = true; _error = null; });
    final client = Supabase.instance.client;
    try {
      final email = _email.text.trim();
      final pass = _password.text;
      if (email.isEmpty || pass.isEmpty) throw Exception('Email & password required');
      final res = await client.auth.signInWithPassword(email: email, password: pass);
      if (res.user == null) {
        // try sign up
        await client.auth.signUp(email: email, password: pass);
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masuk')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')), 
                TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
                const SizedBox(height: 12),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loading ? null : _signInOrUp, child: Text(_loading ? '...' : 'Masuk / Daftar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

