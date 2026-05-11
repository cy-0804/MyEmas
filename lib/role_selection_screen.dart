import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'basic_info_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;

  Future<void> _selectRole(String role) async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No authenticated user found');
      
      await Supabase.instance.client
          .from('users')
          .update({'role_id': role})
          .eq('user_id', user.id);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BasicInfoScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleCard({
    required String title,
    required String description,
    required Color color,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 168,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 20,
              top: 38,
              child: Icon(icon, size: 80, color: color.withOpacity(0.8)),
            ),
            Positioned(
              left: 140,
              top: 35,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Positioned(
              left: 140,
              top: 84,
              right: 16,
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onTap == null)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Coming Soon', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF51A77B)))
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Select Your Role',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF27252E),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 60),
                    _buildRoleCard(
                      title: 'Elderly',
                      description: 'Simple interface, voice commands, and health tracking tools.',
                      color: const Color(0xFF3F8863),
                      icon: Icons.elderly,
                      onTap: () => _selectRole('elderly'),
                    ),
                    const SizedBox(height: 30),
                    _buildRoleCard(
                      title: 'Caregiver',
                      description: 'Remote monitoring, alert management, and caregiver support.',
                      color: const Color(0xFF00539E),
                      icon: Icons.health_and_safety,
                      onTap: null, // Blocked as requested
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
