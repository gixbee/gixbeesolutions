import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main_wrapper.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _nameController = TextEditingController();
  bool _isWorker = false;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = await ref.read(currentUserProvider.future);
      if (user != null) {
        await ref.read(profileRepositoryProvider).updateProfile(
          userId: user.id,
          data: {
            'name': name,
            'role': _isWorker ? 'OPERATOR' : 'OWNER',
            'hasWorkerProfile': _isWorker,
          },
        );
        ref.invalidate(currentUserProvider); // Reload profile info

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainWrapper()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Complete Profile', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DribbbleBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Text(
                  'Welcome to Gixbee!',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Let\'s set up your profile so you can get started.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 48),
                GlassContainer(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Name Input
                      const Text(
                        'Full Name',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'e.g. John Doe',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Role Toggle
                      const Text(
                        'How will you use Gixbee?',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _RoleCard(
                              title: 'Customer',
                              icon: Icons.person_search_rounded,
                              isSelected: !_isWorker,
                              onTap: () => setState(() => _isWorker = false),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _RoleCard(
                              title: 'Worker',
                              icon: Icons.handyman_rounded,
                              isSelected: _isWorker,
                              onTap: () => setState(() => _isWorker = true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),

                      // Submit Button
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Complete & Continue',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white.withValues(alpha: 0.1),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
