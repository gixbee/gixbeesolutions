import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/master_entries_repository.dart';
import '../../shared/models/job_post.dart';

class PostJobScreen extends ConsumerStatefulWidget {
  const PostJobScreen({super.key});

  @override
  ConsumerState<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends ConsumerState<PostJobScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _salaryController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  final List<String> _selectedSkills = [];
  List<String> _availableSkills = []; // Will be fetched from backend

  String _selectedExperience = 'Fresher';
  final List<String> _experienceOptions = ['Fresher', '1-2 yrs', '3-5 yrs', '5+ yrs'];

  String _selectedJobType = 'Full Time';
  final List<String> _jobTypeOptions = ['Full Time', 'Part Time', 'Contract'];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSkills();
  }

  Future<void> _fetchSkills() async {
    try {
      final skills = await ref.read(masterEntriesRepositoryProvider).getByType('SKILL');
      if (mounted) {
        setState(() {
          _availableSkills = skills.map((e) => e.label).toList();
        });
      }
    } catch (e) {
      // Fallback to defaults if API fails
      if (mounted) {
        setState(() {
          _availableSkills = ['General Labor', 'Technician', 'Engineer', 'Designer'];
        });
      }
    }
  }

  void _submitJob() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one skill')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Get user's business
      final businesses = await ref.read(businessRepositoryProvider).getMyBusinesses();
      if (businesses.isEmpty) {
        throw 'You must list a business before you can post a job.';
      }
      final myBusiness = businesses.first;

      // 2. Create JobPost model
      final jobPost = JobPost(
        id: '', 
        title: _titleController.text,
        description: _descriptionController.text,
        requiredSkills: _selectedSkills,
        salaryMin: double.tryParse(_salaryController.text),
        jobType: _selectedJobType,
        experience: _selectedExperience,
        location: _locationController.text,
        isActive: true,
        employerId: myBusiness.id,
      );

      await ref.read(hiringRepositoryProvider).postJob(jobPost);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Job Posted Successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post job: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSkill(String skill) {
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
      } else {
        _selectedSkills.add(skill);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post a Job'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Job Details', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Job Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              Text('Skills Required', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _availableSkills.map((skill) {
                  final isSelected = _selectedSkills.contains(skill);
                  return FilterChip(
                    label: Text(skill),
                    selected: isSelected,
                    onSelected: (_) => _toggleSkill(skill),
                    selectedColor: theme.colorScheme.primaryContainer,
                    checkmarkColor: theme.colorScheme.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedExperience,
                decoration: const InputDecoration(
                  labelText: 'Experience Required',
                  border: OutlineInputBorder(),
                ),
                items: _experienceOptions.map((exp) {
                  return DropdownMenuItem(value: exp, child: Text(exp));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedExperience = val);
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedJobType,
                decoration: const InputDecoration(
                  labelText: 'Job Type',
                  border: OutlineInputBorder(),
                ),
                items: _jobTypeOptions.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedJobType = val);
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _salaryController,
                      decoration: const InputDecoration(
                        labelText: 'Salary (Rs/month)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location/City',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_city),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Job Description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submitJob,
                  child: _isLoading 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Text('Post Job', style: TextStyle(fontSize: 16)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _salaryController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

