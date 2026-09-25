import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../repositories/hiring_repository.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/matching_repository.dart';
import '../../shared/models/job_post.dart';
import '../booking/location_pin_screen.dart';
import 'hiring_master_picker.dart';

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
  final _customSkillController = TextEditingController();

  final List<String> _customSkills = [];
  final Set<String> _skillIds = {};
  List<Map<String, dynamic>> _skillChoices = [];

  String? _positionId;
  String? _positionLabel;
  String? _sectorId;
  String? _locationId;

  String _selectedExperience = 'Fresher';
  final List<String> _experienceOptions = ['Fresher', '1-2 yrs', '3-5 yrs', '5+ yrs'];

  String _selectedJobType = 'Full Time';
  final List<String> _jobTypeOptions = ['Full Time', 'Part Time', 'Contract'];
  String _workMode = 'ONSITE';
  String _salaryPeriod = 'MONTHLY';
  double? _lat;
  double? _lng;

  bool _isLoading = false;
  bool _loadingSkills = false;

  bool get _hasAnySkill => _skillIds.isNotEmpty || _customSkills.isNotEmpty;

  List<String> _requiredSkillLabels() {
    final labels = <String>[];
    for (final id in _skillIds) {
      final row = _skillChoices.cast<Map<String, dynamic>?>().firstWhere(
            (s) => s?['id'] == id,
            orElse: () => null,
          );
      final label = row?['label']?.toString();
      if (label != null && label.isNotEmpty) labels.add(label);
    }
    labels.addAll(_customSkills);
    return labels;
  }

  Future<void> _loadPositionSkills(String positionId) async {
    setState(() {
      _loadingSkills = true;
      _skillChoices = [];
      _skillIds.clear();
    });
    try {
      final detail = await ref.read(matchingRepositoryProvider).hiringPosition(positionId);
      if (!mounted || _positionId != positionId) return;
      final sectors = (detail['sectors'] as List?) ?? [];
      setState(() {
        _sectorId = sectors.isNotEmpty
            ? '${(sectors.first as Map)['id']}'
            : _sectorId;
        _skillChoices = ((detail['skills'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((row) => row['isActive'] != false)
            .toList();
        _loadingSkills = false;
      });
    } catch (_) {
      if (!mounted || _positionId != positionId) return;
      setState(() {
        _loadingSkills = false;
        _skillChoices = [];
      });
    }
  }

  void _toggleCatalogueSkill(String id, String label) {
    setState(() {
      if (_skillIds.contains(id)) {
        _skillIds.remove(id);
      } else {
        _skillIds.add(id);
      }
    });
  }

  void _addCustomSkill() {
    final skill = _customSkillController.text.trim();
    if (skill.isEmpty) return;
    setState(() {
      if (!_customSkills.contains(skill)) _customSkills.add(skill);
      _customSkillController.clear();
    });
  }

  void _submitJob() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasAnySkill) {
      showGxSnack(
        context,
        _positionId == null
            ? 'Pick a position and select at least one skill'
            : 'Select at least one catalogue skill or add a custom skill',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
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

      final locationText = _locationController.text.trim();
      final jobPost = JobPost(
        id: '',
        title: _titleController.text,
        description: _descriptionController.text,
        requiredSkills: _requiredSkillLabels(),
        salaryMin: double.tryParse(_salaryController.text),
        jobType: _selectedJobType,
        experience: _selectedExperience,
        location: locationText,
        isActive: true,
        employerId: '',
        workMode: _workMode,
        salaryPeriod: _salaryPeriod,
        lat: _lat,
        lng: _lng,
        sectorId: _sectorId,
        positionId: _positionId,
        skillIds: _skillIds.toList(),
        locationId: _locationId,
        addressText: locationText,
      );

      await ref.read(hiringRepositoryProvider).postJob(jobPost, businessId: businessId);

      if (!mounted) return;
      showGxSnack(context, 'Job Posted Successfully', type: GxSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to post job: $e', type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _salaryLabel() {
    switch (_salaryPeriod) {
      case 'HOURLY':
        return 'Salary (₹/hour)';
      case 'DAILY':
        return 'Salary (₹/day)';
      case 'WEEKLY':
        return 'Salary (₹/week)';
      case 'PER_JOB':
        return 'Salary (₹/job)';
      default:
        return 'Salary (₹/month)';
    }
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
              Text('Job Details',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GxTextField(
                controller: _titleController,
                label: 'Job Title',
                prefixIcon: Icons.work,
                accent: GixbeeTheme.accentBlue,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Text('Position (catalogue)', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Search the same roles as Hire Employee — skills load from the master.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              if (_positionLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Selected: $_positionLabel',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              HiringPositionSearch(
                sectorId: _sectorId,
                selectedLabel: _positionLabel,
                onPick: (pick) {
                  setState(() {
                    _positionId = pick.id;
                    _positionLabel = pick.label;
                    if (_titleController.text.trim().isEmpty) {
                      _titleController.text = pick.label;
                    }
                  });
                  _loadPositionSkills(pick.id);
                },
              ),
              const SizedBox(height: 16),
              Text('Skills Required', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_loadingSkills) const LinearProgressIndicator(),
              if (_positionId == null && !_loadingSkills)
                Text(
                  'Pick a position above to see catalogue skills.',
                  style: theme.textTheme.bodySmall,
                ),
              if (_positionId != null && !_loadingSkills && _skillChoices.isEmpty)
                Text(
                  'No catalogue skills for this role — add custom skills below.',
                  style: theme.textTheme.bodySmall,
                ),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  for (final row in _skillChoices)
                    FilterChip(
                      label: Text('${row['label']}'),
                      selected: _skillIds.contains('${row['id']}'),
                      onSelected: (_) => _toggleCatalogueSkill('${row['id']}', '${row['label']}'),
                      selectedColor: GixbeeTheme.accentBlue.withValues(alpha: 0.18),
                      checkmarkColor: GixbeeTheme.accentBlue,
                    ),
                  for (final skill in _customSkills)
                    InputChip(
                      label: Text(skill),
                      onDeleted: () => setState(() => _customSkills.remove(skill)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customSkillController,
                      decoration: const InputDecoration(
                        hintText: 'Add another skill',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addCustomSkill(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addCustomSkill,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedExperience,
                decoration: const InputDecoration(
                  labelText: 'Experience Required',
                  border: OutlineInputBorder(),
                ),
                items: _experienceOptions
                    .map((exp) => DropdownMenuItem(value: exp, child: Text(exp)))
                    .toList(),
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
                items: _jobTypeOptions
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
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
              GxTextField(
                controller: _salaryController,
                label: _salaryLabel(),
                prefixIcon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
                accent: GixbeeTheme.accentBlue,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Text('City / town', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              HiringLocationSearch(
                selectedLabel: _locationId == null ? null : _locationController.text,
                onPick: (pick) {
                  setState(() {
                    _locationId = pick.id;
                    _locationController.text = pick.label;
                    if (pick.lat != null && pick.lng != null) {
                      _lat = pick.lat;
                      _lng = pick.lng;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              GxButton(
                label: _lat == null ? 'Pin exact location (optional)' : 'Location pinned',
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
    _customSkillController.dispose();
    super.dispose();
  }
}
