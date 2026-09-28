import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../repositories/hiring_repository.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/master_entries_repository.dart';
import '../../shared/models/job_post.dart';
import '../booking/location_pin_screen.dart';

class PostJobScreen extends ConsumerStatefulWidget {
  final String? businessId;
  const PostJobScreen({super.key, this.businessId});

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
  String _workMode = 'ONSITE';
  String _salaryPeriod = 'MONTHLY';
  double? _lat;
  double? _lng;

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
      showGxSnack(context, 'Please select at least one skill');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Get user's business
      final businesses = await ref.read(businessRepositoryProvider).getMyBusinesses();
      final hiring = businesses
          .where((b) => b.type == 'HIRING' && b.status == 'VERIFIED')
          .toList();
      var businessId = widget.businessId;
      if (businessId == null && hiring.length == 1) {
        businessId = hiring.first.id;
      } else if (businessId == null && hiring.length > 1) {
        if (!mounted) return;
        businessId = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Which business is posting?'),
            children: [
              for (final business in hiring)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, business.id),
                  child: Text(business.name),
                ),
            ],
          ),
        );
        if (businessId == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }
      if (businessId == null) {
        throw 'A verified hiring business is required before you can post a job.';
      }

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
        employerId: '',
        workMode: _workMode,
        salaryPeriod: _salaryPeriod,
        lat: _lat,
        lng: _lng,
      );

      await ref.read(hiringRepositoryProvider).postJob(jobPost, businessId: businessId);

      if (!mounted) return;
      showGxSnack(context, 'Job Posted Successfully',
          type: GxSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to post job: $e',
            type: GxSnackType.error);
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
              
              GxTextField(
                controller: _titleController,
                label: 'Job Title',
                prefixIcon: Icons.work,
                accent: GixbeeTheme.accentBlue,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
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
                    selectedColor: GixbeeTheme.accentBlue.withValues(alpha: 0.18),
                    checkmarkColor: GixbeeTheme.accentBlue,
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
              Text('Work mode', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in const ['ONSITE', 'HYBRID', 'REMOTE'])
                    ChoiceChip(
                      label: Text(mode == 'ONSITE'
                          ? 'On-site'
                          : mode == 'HYBRID'
                              ? 'Hybrid'
                              : 'Remote'),
                      selected: _workMode == mode,
                      onSelected: (_) => setState(() => _workMode = mode),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _salaryPeriod,
                decoration: const InputDecoration(
                  labelText: 'Salary period',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                  DropdownMenuItem(value: 'DAILY', child: Text('Daily')),
                  DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
                  DropdownMenuItem(value: 'HOURLY', child: Text('Hourly')),
                  DropdownMenuItem(value: 'PER_JOB', child: Text('Per job')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _salaryPeriod = val);
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: GxTextField(
                      controller: _salaryController,
                      label: 'Salary (Rs/month)',
                      prefixIcon: Icons.currency_rupee,
                      keyboardType: TextInputType.number,
                      accent: GixbeeTheme.accentBlue,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GxTextField(
                      controller: _locationController,
                      label: 'Location/City',
                      prefixIcon: Icons.location_city,
                      accent: GixbeeTheme.accentBlue,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GxButton(
                label: _lat == null ? 'Pin exact location' : 'Location pinned',
                filled: false,
                accent: GixbeeTheme.accentBlue,
                height: 46,
                onTap: () async {
                  final result = await Navigator.push<PinnedLocation>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationPinScreen(
                        initialLat: _lat ?? 8.5241,
                        initialLng: _lng ?? 76.9366,
                        initialAddress: _locationController.text.trim().isEmpty
                            ? null
                            : _locationController.text.trim(),
                      ),
                    ),
                  );
                  if (result == null || !mounted) return;
                  setState(() {
                    _lat = result.lat;
                    _lng = result.lng;
                    if (result.address.trim().isNotEmpty) {
                      _locationController.text = result.address.trim();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              GxTextField(
                controller: _descriptionController,
                label: 'Job Description',
                maxLines: 4,
                accent: GixbeeTheme.accentBlue,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),

              const SizedBox(height: 32),

              GxButton(
                label: 'Post Job',
                onTap: _isLoading ? null : _submitJob,
                loading: _isLoading,
                gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
                accent: GixbeeTheme.accentBlue,
                height: 50,
                fontSize: 16,
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

