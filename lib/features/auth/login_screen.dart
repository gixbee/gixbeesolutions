import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/auth_repository.dart';
import '../../core/config/app_config.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: DribbbleBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),

                  // Back Button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon:
                          const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'Welcome Back',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your phone number to continue',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                  ),

                  const SizedBox(height: 48),

                  // Phone Input
                  GlassContainer(
                    child: GestureDetector(
                      onTap: () => _focusNode.requestFocus(),
                      behavior: HitTestBehavior.opaque,
                      child: TextField(
                        controller: _phoneController,
                        focusNode: _focusNode,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        decoration: InputDecoration(
                          hintText: '98765 43210',
                          prefixText: '${AppConfig.defaultCountryCode} ',
                          prefixStyle: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.phone, color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Continue Button
                  ElevatedButton(
                    onPressed: () async {
                      var phone = _phoneController.text.trim();
                      
                      // Firebase Auth REQUIRES the + prefix (e.g., +91...)
                      if (!phone.startsWith('+')) {
                        // Default to India (+91) if prefix is missing for convenience, 
                        // but tell the user to be sure.
                        phone = '${AppConfig.defaultCountryCode}$phone'; 
                        debugPrint('Prefixing phone with ${AppConfig.defaultCountryCode}: $phone');
                      }

                      if (phone.length < AppConfig.phoneMinLength) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid phone number (e.g., +91 9605...)')),
                        );
                        return;
                      }

                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref.read(authRepositoryProvider).signInWithPhone(phone);
                          
                          if (!mounted) return;
                          
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OtpScreen(
                                phone: phone,
                              ),
                            ),
                          );
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Supabase Error: $e')),
                            );
                          }
                        }
                    },
                    // Removed style: ElevatedButton.styleFrom(...) because M3 theme handles it globally
                    child: const Text(
                      'Send Code',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Just enter your phone number to start!')),
                        );
                      },
                      child: Text(
                        'New to Gixbee? Register here',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}
