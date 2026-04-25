import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/talent_repository.dart';

const List<String> _availableSkills = [
  'Electrician', 'Plumber', 'Driver', 'Cleaner',
  'Nurse', 'Caregiver', 'Painter', 'Carpenter',
  'AC Technician', 'Security Guard', 'Cook', 'Gardener',
];

class RegisterProScreen extends ConsumerStatefulWidget {
  const RegisterProScreen({super.key});

  @override
  ConsumerState<RegisterProScreen> createState() => _RegisterProScreenState();
}

class _RegisterProScreenState extends ConsumerState<RegisterProScreen> {
  List<dynamic> _professionalSkills = [];
  String? _selectedSkillName;
  final TextEditingController _newSkillRateController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoading = true;
  String? _approvalStatus;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  bool _isEditing = false;

  Future<void> _fetchProfile() async {
    try {
      final profile = await ref.read(talentRepositoryProvider).getProfile();
      if (mounted) {
        setState(() {
          _professionalSkills = profile['professionalSkills'] as List? ?? [];
          _bioController.text = (profile['experience'] ?? '').toString();
          
          if (profile['user'] != null) {
            _approvalStatus = profile['user']['approvalStatus'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Fetch profile failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _newSkillRateController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _startEditing(Map<String, dynamic> skill) {
    setState(() {
      _isEditing = true;
      _selectedSkillName = skill['name'];
      _newSkillRateController.text = skill['hourlyRate'].toString();
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _selectedSkillName = null;
      _newSkillRateController.clear();
    });
  }

  Future<void> _addSkill() async {
    if (_selectedSkillName == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a skill')));
      return;
    }
    final rate = double.tryParse(_newSkillRateController.text);
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid rate')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(talentRepositoryProvider).addOrUpdateSkill(_selectedSkillName!, rate);
      _newSkillRateController.clear();
      _selectedSkillName = null;
      _isEditing = false;
      await _fetchProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skill updated successfully!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save skill: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _removeSkill(String skillId) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(talentRepositoryProvider).removeSkill(skillId);
      await _fetchProfile();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove skill: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitBio() async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(talentRepositoryProvider).updateProfile({
        'experience': _bioController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register as Pro'),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Earn by Working',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Register your skills, get verified, and start earning hourly.\nFirst job is free — Rs.12 wallet balance required after that.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),

            if (_approvalStatus != null && (_professionalSkills.isNotEmpty || _bioController.text.trim().isNotEmpty)) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getStatusColor(_approvalStatus!).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getStatusColor(_approvalStatus!).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_getStatusIcon(_approvalStatus!), color: _getStatusColor(_approvalStatus!), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Profile Status: ${_approvalStatus!.toUpperCase()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(_approvalStatus!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Active Skills Section
            Text('Your Registered Skills',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_professionalSkills.isEmpty)
              const Text('No skills added yet. Add your first skill below.', style: TextStyle(color: Colors.grey, fontSize: 13))
            else
              Column(
                children: _professionalSkills.map((skill) {
                  final status = skill['status'] ?? 'PENDING';
                  final isCurrentlyEditing = _isEditing && _selectedSkillName == skill['name'];
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isCurrentlyEditing ? colorScheme.primary : colorScheme.outlineVariant,
                        width: isCurrentlyEditing ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(skill['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Row(
                        children: [
                          Text('₹${skill['hourlyRate']}/hr', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _getStatusColor(status))),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                            onPressed: () => _startEditing(skill),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _removeSkill(skill['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // Add New Skill Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isEditing ? 'Update Skill Rate' : 'Add New Skill',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (_isEditing)
                  TextButton.icon(
                    onPressed: _cancelEditing,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancel Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_isEditing ? 'Adjust your hourly rate for $_selectedSkillName.' : 'Select a skill and set your hourly rate for it.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            
            if (!_isEditing)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSkills.map((skill) {
                  // Hide if already added
                  final isAdded = _professionalSkills.any((s) => s['name'] == skill);
                  if (isAdded) return const SizedBox.shrink();

                  final selected = _selectedSkillName == skill;
                  return FilterChip(
                    label: Text(skill),
                    selected: selected,
                    onSelected: (val) {
                      setState(() {
                        _selectedSkillName = val ? skill : null;
                      });
                    },
                    selectedColor: colorScheme.primaryContainer,
                    checkmarkColor: colorScheme.primary,
                  );
                }).toList(),
              ),

            if (_selectedSkillName != null) ...[
              const SizedBox(height: 24),
              Text('Rate for $_selectedSkillName (Rs./hr)', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newSkillRateController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g. 200',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _addSkill,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_isEditing ? 'Update' : 'Add'),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 40),

            // Bio remains pretty much the same but needs its own submit
            Text('Expertise Bio',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Tell customers about your experience...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _submitBio,
                child: const Text('Update Bio'),
              ),
            ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Icons.verified;
      case 'rejected': return Icons.cancel;
      case 'pending': return Icons.hourglass_top;
      default: return Icons.info;
    }
  }

}

